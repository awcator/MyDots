// Command wa is a minimal WhatsApp CLI for Linux.
//
// It talks to WhatsApp over the Multi-Device protocol (via whatsmeow) and
// persists the session in a local SQLite file, so the QR code only needs to
// be scanned once. After that, messages can be sent programmatically.
//
// Usage:
//
//	wa login                 # print a QR code and wait for you to scan it
//	wa login-code <phone>    # pair via "Link with phone number" (8-char code)
//	wa send <recip> <text>   # send a text message
//	wa status                # show login state
//
// <recip> may be:
//   - "self" or "me"        -> your own "Message yourself" chat
//   - a phone number        -> e.g. "15551234567" or "+15551234567"
//   - a full JID            -> e.g. "15551234567@s.whatsapp.net" or "123@g.us"
package main

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	_ "modernc.org/sqlite"

	"github.com/mdp/qrterminal/v3"
	"github.com/purpshell/meowcaller"
	"github.com/rs/zerolog"
	"go.mau.fi/whatsmeow"
	waProto "go.mau.fi/whatsmeow/binary/proto"
	"go.mau.fi/whatsmeow/store/sqlstore"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
	waLog "go.mau.fi/whatsmeow/util/log"
	"google.golang.org/protobuf/proto"
)

const dbFile = "whatsapp.db"

// defaultRecipient is the watch number the bot always messages/calls. It lives
// only here — compiled into the binary — not in settings, prompts, or scripts.
const defaultRecipient = "91xxxxxxxxx"

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func run() error {
	ctx := context.Background()

	// Open the SQLite store with a single serialized connection and a busy
	// timeout. SQLite only allows one writer at a time, so the default
	// connection pool (one connection per goroutine) leads to "database is
	// locked" errors under whatsmeow's concurrent reads/writes.
	//
	// The store path is FIXED and independent of the binary's location:
	// WA_DIR if set, else ~/.local/share/wa. This way the binary finds its
	// session no matter where it is invoked from (not tied to os.Executable,
	// which broke when a copy lived in ~/go/bin).
	dbDir := os.Getenv("WA_DIR")
	if dbDir == "" {
		if home, err := os.UserHomeDir(); err == nil {
			dbDir = filepath.Join(home, ".local", "share", "wa")
		}
	}
	if err := os.MkdirAll(dbDir, 0700); err != nil {
		return fmt.Errorf("create store dir: %w", err)
	}
	dsn := "file:" + filepath.Join(dbDir, dbFile) + "?_foreign_keys=on&_busy_timeout=10000&_txlock=immediate"
	rawDB, err := sql.Open("sqlite", dsn)
	if err != nil {
		return fmt.Errorf("open store: %w", err)
	}
	rawDB.SetMaxOpenConns(1)

	container := sqlstore.NewWithDB(rawDB, "sqlite", waLog.Noop)
	if err := container.Upgrade(ctx); err != nil {
		return fmt.Errorf("upgrade store: %w", err)
	}
	deviceStore, err := container.GetFirstDevice(ctx)
	if err != nil {
		return fmt.Errorf("load device: %w", err)
	}

	client := whatsmeow.NewClient(deviceStore, waLog.Noop)

	switch {
	case len(os.Args) < 2:
		usage()
		return nil
	case os.Args[1] == "login":
		return login(ctx, client)
	case os.Args[1] == "login-code":
		if len(os.Args) < 3 {
			return errors.New("usage: wa login-code <your-phone-number>")
		}
		return loginCode(ctx, client, os.Args[2])
	case os.Args[1] == "send":
		if len(os.Args) < 3 {
			return errors.New("usage: wa send <message>")
		}
		return send(ctx, client, defaultRecipient, strings.Join(os.Args[2:], " "))
	case os.Args[1] == "call":
		audioFile := ""
		if len(os.Args) >= 3 {
			audioFile = os.Args[2]
		}
		return call(ctx, client, defaultRecipient, audioFile)
	case os.Args[1] == "status":
		return status(ctx, client)
	default:
		usage()
		return fmt.Errorf("unknown command %q", os.Args[1])
	}
}

func usage() {
	fmt.Println(`usage:
  wa login                 # scan QR code once to log in
  wa login-code <phone>    # pair via "Link with phone number" (8-char code)
  wa send <text>           # send a message to the watch number
  wa call [audio]          # call the watch number; ring, then hang up (or play audio)
  wa status                # show login state`)
}

// login connects to WhatsApp and, if no session exists yet, prints a QR code
// to the terminal and waits for the user to scan it with their phone.
func login(ctx context.Context, client *whatsmeow.Client) error {
	if client.Store.ID != nil {
		fmt.Printf("already logged in as %s\n", client.Store.ID.User)
		return connectAndWait(ctx, client)
	}

	ready := make(chan struct{})
	client.AddEventHandler(func(evt any) {
		switch v := evt.(type) {
		case *events.QR:
			for _, code := range v.Codes {
				fmt.Println("\nScan this QR code with WhatsApp on your phone")
				fmt.Println("(WhatsApp → Settings → Linked devices → Link a device)")
				qrterminal.GenerateHalfBlock(code, qrterminal.L, os.Stdout)
			}
		case *events.PairSuccess:
			fmt.Printf("\n✅ paired as %s\n", v.ID.User)
		case *events.Connected:
			fmt.Println("✅ connected")
			select {
			case <-ready:
			default:
				close(ready)
			}
		}
	})

	if err := client.Connect(); err != nil {
		return fmt.Errorf("connect: %w", err)
	}
	defer client.Disconnect()

	fmt.Println("waiting for you to scan the QR code...")
	waitFor(ctx, ready)
	return nil
}

// loginCode pairs using WhatsApp's "Link with phone number" flow: instead of
// scanning a QR code, you get an 8-character code to type into the phone.
// This is more reliable than QR linking, which occasionally fails with
// "couldn't link, try again later".
func loginCode(ctx context.Context, client *whatsmeow.Client, phone string) error {
	if client.Store.ID != nil {
		fmt.Printf("already logged in as %s\n", client.Store.ID.User)
		return nil
	}

	qrReceived := make(chan struct{})
	ready := make(chan struct{})
	client.AddEventHandler(func(evt any) {
		switch v := evt.(type) {
		case *events.QR:
			// We ignore the QR code, but its arrival means the connection is
			// established and it is safe to call PairPhone.
			select {
			case <-qrReceived:
			default:
				close(qrReceived)
			}
		case *events.PairSuccess:
			fmt.Printf("\n✅ paired as %s\n", v.ID.User)
		case *events.Connected:
			fmt.Println("✅ connected")
			select {
			case <-ready:
			default:
				close(ready)
			}
		}
	})

	if err := client.Connect(); err != nil {
		return fmt.Errorf("connect: %w", err)
	}
	defer client.Disconnect()

	// Wait until the login websocket is up before requesting a code.
	waitFor(ctx, qrReceived)

	code, err := client.PairPhone(ctx, phone, false, whatsmeow.PairClientChrome, "Chrome (Linux)")
	if err != nil {
		return fmt.Errorf("request pairing code: %w", err)
	}

	fmt.Printf("\nEnter this 8-character code on your phone:\n\n    %s\n\n", code)
	fmt.Println("(WhatsApp → Settings → Linked devices → Link with phone number)")
	fmt.Println("waiting for you to enter the code...")
	waitFor(ctx, ready)
	return nil
}

func status(ctx context.Context, client *whatsmeow.Client) error {
	if client.Store.ID == nil {
		fmt.Println("not logged in (run `wa login`)")
		return nil
	}
	fmt.Printf("logged in as %s\n", client.Store.ID.User)
	return nil
}

func send(ctx context.Context, client *whatsmeow.Client, recip, text string) error {
	if client.Store.ID == nil {
		return errors.New("not logged in — run `wa login` first")
	}

	to, err := resolveRecipient(client, recip)
	if err != nil {
		return err
	}

	// Connect (idempotent) and wait until the socket is ready.
	ready := make(chan struct{})
	client.AddEventHandler(func(evt any) {
		if _, ok := evt.(*events.Connected); ok {
			select {
			case <-ready:
			default:
				close(ready)
			}
		}
	})
	if err := client.Connect(); err != nil {
		return fmt.Errorf("connect: %w", err)
	}
	defer client.Disconnect()
	waitFor(ctx, ready)

	msg := &waProto.Message{Conversation: proto.String(text)}
	resp, err := client.SendMessage(ctx, to, msg)
	if err != nil {
		return fmt.Errorf("send: %w", err)
	}
	fmt.Printf("✅ sent to %s (id %s)\n", to.String(), resp.ID)
	return nil
}

// call places a 1:1 WhatsApp voice call to recip. With an audio file it plays that
// file to the peer once they answer, then hangs up; without one it is an "empty"
// call that rings for ~30s and hangs up.
func call(ctx context.Context, client *whatsmeow.Client, recip, audioFile string) error {
	if client.Store.ID == nil {
		return errors.New("not logged in — run `wa login` first")
	}
	to, err := resolveRecipient(client, recip)
	if err != nil {
		return err
	}

	// Wrap with meowcaller BEFORE connecting so its call handlers are installed
	// before the receive loop starts. Debug/trace via MEOW_LOG_LEVEL=debug.
	meowLevel := zerolog.WarnLevel
	if lvl, err := zerolog.ParseLevel(os.Getenv("MEOW_LOG_LEVEL")); err == nil && lvl != zerolog.NoLevel {
		meowLevel = lvl
	}
	meowLog := zerolog.New(zerolog.ConsoleWriter{Out: os.Stderr, TimeFormat: "15:04:05.000"}).
		Level(meowLevel).With().Timestamp().Logger()
	mc := meowcaller.NewClient(client, meowcaller.WithLogger(meowLog))

	ready := make(chan struct{})
	client.AddEventHandler(func(evt any) {
		if _, ok := evt.(*events.Connected); ok {
			select {
			case <-ready:
			default:
				close(ready)
			}
		}
	})
	if err := client.Connect(); err != nil {
		return fmt.Errorf("connect: %w", err)
	}
	defer client.Disconnect()
	waitFor(ctx, ready)

	// Announce presence so the server delivers call signaling to us.
	if client.Store.PushName == "" {
		client.Store.PushName = "wa-bot"
	}
	_ = client.SendPresence(ctx, types.PresenceAvailable)

	callObj, err := mc.Call(ctx, to.String())
	if err != nil {
		return fmt.Errorf("place call: %w", err)
	}
	fmt.Printf("📞 calling %s (id %s)\n", to.String(), callObj.ID())

	endCh := make(chan struct{})
	callObj.OnEnd(func(reason string) {
		fmt.Printf("📴 call ended: %s\n", reason)
		select {
		case <-endCh:
		default:
			close(endCh)
		}
	})

	// Always hang up after a ring window if the call hasn't ended by then
	// (covers "peer didn't answer" for both empty and audio calls).
	go func() {
		select {
		case <-time.After(45 * time.Second):
			fmt.Println("⏰ ring window elapsed — hanging up")
			_ = callObj.Hangup()
		case <-endCh:
		case <-ctx.Done():
		}
	}()

	if audioFile != "" {
		src, err := openAudioSource(audioFile)
		if err != nil {
			_ = callObj.Hangup()
			return fmt.Errorf("open audio: %w", err)
		}
		callObj.OnReady(func() {
			fmt.Println("📣 peer answered — playing audio")
			p := callObj.Play(src)
			p.OnFinish(func() {
				fmt.Println("⏹ audio finished — hanging up")
				_ = callObj.Hangup()
			})
		})
	}

	// Block until the call ends (peer hangs up, we hang up, or interrupted).
	select {
	case <-endCh:
	case <-ctx.Done():
		_ = callObj.Hangup()
	}
	return nil
}

// openAudioSource opens a .mp3/.wav/.opus file as a meowcaller AudioSource.
func openAudioSource(path string) (meowcaller.AudioSource, error) {
	switch strings.ToLower(filepath.Ext(path)) {
	case ".mp3":
		return meowcaller.MP3File(path)
	case ".wav":
		return meowcaller.WAVFile(path)
	case ".opus":
		return meowcaller.OpusFile(path)
	default:
		return nil, fmt.Errorf("unsupported audio extension %q (want .mp3/.wav/.opus)", filepath.Ext(path))
	}
}

// resolveRecipient turns a user-friendly argument into a WhatsApp JID.
func resolveRecipient(client *whatsmeow.Client, arg string) (types.JID, error) {
	switch strings.ToLower(arg) {
	case "self", "me":
		return client.Store.ID.ToNonAD(), nil
	}

	if strings.Contains(arg, "@") {
		return types.ParseJID(arg)
	}

	digits := strings.TrimSpace(strings.TrimPrefix(arg, "+"))
	digits = strings.Map(func(r rune) rune {
		if r >= '0' && r <= '9' {
			return r
		}
		return -1
	}, digits)
	if digits == "" {
		return types.EmptyJID, fmt.Errorf("invalid recipient %q", arg)
	}
	return types.NewJID(digits, types.DefaultUserServer), nil
}

// connectAndWait is used after an already-stored session: connect and wait
// until the client reports it is connected.
func connectAndWait(ctx context.Context, client *whatsmeow.Client) error {
	ready := make(chan struct{})
	client.AddEventHandler(func(evt any) {
		if _, ok := evt.(*events.Connected); ok {
			select {
			case <-ready:
			default:
				close(ready)
			}
		}
	})
	if err := client.Connect(); err != nil {
		return fmt.Errorf("connect: %w", err)
	}
	defer client.Disconnect()
	waitFor(ctx, ready)
	return nil
}

// waitFor blocks until ready is closed, the context is cancelled, or the user
// interrupts with Ctrl-C.
func waitFor(ctx context.Context, ready <-chan struct{}) {
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
	defer signal.Stop(sig)

	select {
	case <-ready:
	case <-ctx.Done():
	case <-sig:
		fmt.Fprintln(os.Stderr, "\ninterrupted")
	}
}
