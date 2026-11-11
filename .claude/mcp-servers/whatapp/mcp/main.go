// Command wa-mcp is a Model Context Protocol (MCP) server that lets an AI
// agent (e.g. Claude Code) send WhatsApp messages, images, and files by
// shelling out to the `wa` CLI.
//
// Configuration (all optional, via environment variables):
//
//	WA_BIN    path to the `wa` binary          (default: <WA_DIR>/wa, then "wa" on PATH)
//	WA_DIR    working dir for the `wa` binary  (default: ~/.claude/mcp-servers/whatapp)
//	TTS_BIN   path to edge-tts                 (default: <WA_DIR>/tts-venv/bin/edge-tts,
//	          then "edge-tts" on PATH)
//	TTS_VOICE neural voice for TTS             (default: "en-US-AriaNeural")
package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/mark3labs/mcp-go/mcp"
	"github.com/mark3labs/mcp-go/server"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func run() error {
	waDir := os.Getenv("WA_DIR")
	if waDir == "" {
		if home, err := os.UserHomeDir(); err == nil {
			waDir = filepath.Join(home, ".claude", "mcp-servers", "whatapp")
		}
	}

	waBin := os.Getenv("WA_BIN")
	if waBin == "" {
		localBin := filepath.Join(waDir, "wa")
		if _, err := os.Stat(localBin); err == nil {
			waBin = localBin
		} else {
			waBin = "wa"
		}
	}

	ttsVoice := os.Getenv("TTS_VOICE")
	if ttsVoice == "" {
		ttsVoice = "en-US-AriaNeural"
	}

	s := server.NewMCPServer(
		"whatsapp",
		"1.0.0",
		server.WithToolCapabilities(true),
	)

	// runWa executes the wa CLI command with unified error handling and formatting.
	runWa := func(ctx context.Context, args ...string) (*mcp.CallToolResult, error) {
		cmd := exec.CommandContext(ctx, waBin, args...)
		cmd.Dir = waDir
		out, err := cmd.CombinedOutput()
		if err != nil {
			return mcp.NewToolResultError(fmt.Sprintf("failed: %v: %s", err, out)), nil
		}
		return mcp.NewToolResultText(string(out)), nil
	}

	// 1. send_message
	sendTool := mcp.NewTool("send_message",
		mcp.WithDescription(
			"WhatsApp the operator. Use to notify, ping, report done, or escalate a "+
				"blocked decision."),
		mcp.WithString("message",
			mcp.Required(),
			mcp.Description("The message text to send."),
		),
		mcp.WithString("image_path",
			mcp.Description("Optional path to an image to send with the message as caption."),
		),
		mcp.WithString("attachment_path",
			mcp.Description("Optional path to a file/document to send with the message as caption."),
		),
	)
	s.AddTool(sendTool, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		args, _ := req.Params.Arguments.(map[string]any)

		message, _ := args["message"].(string)
		if img, _ := args["image_path"].(string); img == "" {
			img, _ = args["image"].(string)
			if img != "" {
				cmdArgs := []string{"send-image", resolvePath(img)}
				if message != "" {
					cmdArgs = append(cmdArgs, message)
				}
				return runWa(ctx, cmdArgs...)
			}
		} else {
			cmdArgs := []string{"send-image", resolvePath(img)}
			if message != "" {
				cmdArgs = append(cmdArgs, message)
			}
			return runWa(ctx, cmdArgs...)
		}

		if file, _ := args["attachment_path"].(string); file == "" {
			file, _ = args["attachment"].(string)
			if file == "" {
				file, _ = args["file"].(string)
			}
			if file != "" {
				cmdArgs := []string{"send-file", resolvePath(file)}
				if message != "" {
					cmdArgs = append(cmdArgs, message)
				}
				return runWa(ctx, cmdArgs...)
			}
		} else {
			cmdArgs := []string{"send-file", resolvePath(file)}
			if message != "" {
				cmdArgs = append(cmdArgs, message)
			}
			return runWa(ctx, cmdArgs...)
		}

		if message == "" {
			return mcp.NewToolResultError("missing required parameter: message"), nil
		}
		return runWa(ctx, "send", message)
	})

	// 2. send_image
	handleSendImage := func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		args, _ := req.Params.Arguments.(map[string]any)

		path, _ := args["path"].(string)
		if path == "" {
			path, _ = args["image_path"].(string)
		}
		if path == "" {
			path, _ = args["file_path"].(string)
		}
		if path == "" {
			return mcp.NewToolResultError("missing required parameter: path"), nil
		}

		cmdArgs := []string{"send-image", resolvePath(path)}
		if caption, _ := args["caption"].(string); caption != "" {
			cmdArgs = append(cmdArgs, caption)
		}
		return runWa(ctx, cmdArgs...)
	}

	sendImageTool := mcp.NewTool("send_image",
		mcp.WithDescription(
			"Send an image (PNG/JPG/GIF/WebP) with an optional caption."),
		mcp.WithString("path",
			mcp.Required(),
			mcp.Description("Image file path."),
		),
		mcp.WithString("caption",
			mcp.Description("Optional caption for the image."),
		),
	)
	s.AddTool(sendImageTool, handleSendImage)

	// 3. send_file
	handleSendFile := func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		args, _ := req.Params.Arguments.(map[string]any)

		path, _ := args["path"].(string)
		if path == "" {
			path, _ = args["file_path"].(string)
		}
		if path == "" {
			path, _ = args["attachment"].(string)
		}
		if path == "" {
			return mcp.NewToolResultError("missing required parameter: path"), nil
		}

		cmdArgs := []string{"send-file", resolvePath(path)}
		if caption, _ := args["caption"].(string); caption != "" {
			cmdArgs = append(cmdArgs, caption)
		}
		return runWa(ctx, cmdArgs...)
	}

	sendFileTool := mcp.NewTool("send_file",
		mcp.WithDescription(
			"Send a document/file (PDF, log, zip, code…) with an optional caption."),
		mcp.WithString("path",
			mcp.Required(),
			mcp.Description("File path."),
		),
		mcp.WithString("caption",
			mcp.Description("Optional caption or description for the attachment."),
		),
	)
	s.AddTool(sendFileTool, handleSendFile)


	// 4. call
	callTool := mcp.NewTool("call",
		mcp.WithDescription(
			"Call the operator (rings ~30s). Give `text` (local emotional TTS, voice Nova) or "+
				"an `audio` file. They can't see your screen, so make it a REAL, interesting "+
				"call: a vivid scene with story and specifics, not a one-liner. "+
				"HARD LIMIT: 30 words max, audio clipped to 15 seconds; text is truncated "+
				"and quote marks stripped automatically. No double quotes in the text. "+
				"Inline mood tags render as real sounds/tones — use 2-3 per call, varied, "+
				"where a human would react: "+
				"[whispering] [sigh] [groan] [crying] [sniff] [laugh] [chuckle] [gasp] "+
				"[surprised] [happy] [angry] [fear] [sarcastic] [dramatic] [narration] "+
				"[advertisement] [shush] [cough] [clear throat]. "+
				"Intimate: [whispering]/[sigh]/[groan]. Celebratory: [happy]/[laugh]. "+
				"Write short sentences with real punctuation — long run-ons render fast and "+
				"flat. Renders before it dials."),
		mcp.WithString("text",
			mcp.Description("Spoken text; all 19 mood/emotion tags available (see tool description). Takes precedence over `audio`."),
		),
		mcp.WithString("audio",
			mcp.Description("Optional path to an audio file (.mp3/.wav/.opus) to play when the call is answered."),
		),
	)
	s.AddTool(callTool, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		args, _ := req.Params.Arguments.(map[string]any)

		audio, _ := args["audio"].(string)
		if text, _ := args["text"].(string); text != "" {
			ttsBin := resolveTTSBin(waDir)
			path, err := generateSpeech(ctx, ttsBin, ttsVoice, sanitizeCallText(text), os.TempDir())
			if err != nil {
				return mcp.NewToolResultError(err.Error()), nil
			}
			defer os.Remove(path)
			if err := clipAudio(path, 15); err != nil {
				return mcp.NewToolResultError(err.Error()), nil
			}
			audio = path
		}

		cmdArgs := []string{"call"}
		if audio != "" {
			cmdArgs = append(cmdArgs, audio)
		}
		return runWa(ctx, cmdArgs...)
	})

	return server.ServeStdio(s)
}

// sanitizeCallText strips quote marks and caps the spoken text at 30 words,
// since the call audio must stay short. Mood tags count as words.
func sanitizeCallText(text string) string {
	text = strings.NewReplacer(`"`, "", "“", "", "”", "", "„", "", "«", "", "»", "").Replace(text)
	words := strings.Fields(text)
	if len(words) > 30 {
		words = words[:30]
	}
	return strings.Join(words, " ")
}

// clipAudio trims an audio file to at most maxSec seconds with a short fade
// out. The fade start is past the end of shorter files, so it is a no-op there.
func clipAudio(path string, maxSec int) error {
	tmp := path + ".clip"
	af := fmt.Sprintf("afade=t=out:st=%d.7:d=0.3", maxSec-1)
	cmd := exec.Command("ffmpeg", "-y", "-loglevel", "error", "-i", path,
		"-af", af, "-t", strconv.Itoa(maxSec), "-b:a", "48k", "-f", "mp3", tmp)
	if out, err := cmd.CombinedOutput(); err != nil {
		os.Remove(tmp)
		return fmt.Errorf("clip audio: %v: %s", err, out)
	}
	return os.Rename(tmp, path)
}

// resolveTTSBin locates the edge-tts executable.
func resolveTTSBin(waDir string) string {
	if env := os.Getenv("TTS_BIN"); env != "" {
		if _, err := os.Stat(env); err == nil {
			return env
		}
	}
	candidates := []string{
		filepath.Join(waDir, "tts-venv", "bin", "edge-tts"),
	}
	if home, err := os.UserHomeDir(); err == nil {
		candidates = append(candidates,
			filepath.Join(home, ".local", "bin", "edge-tts"),
			filepath.Join(home, ".claude", "mcp-servers", "whatapp", "tts-venv", "bin", "edge-tts"),
			filepath.Join(home, "Documents", "MyDots", ".claude", "mcp-servers", "whatapp", "tts-venv", "bin", "edge-tts"),
		)
	}
	for _, candidate := range candidates {
		if _, err := os.Stat(candidate); err == nil {
			return candidate
		}
	}
	if p, err := exec.LookPath("edge-tts"); err == nil {
		return p
	}
	return candidates[0]
}

// resolvePath returns the clean absolute path for a given path string.
func resolvePath(p string) string {
	if p == "" {
		return ""
	}
	if filepath.IsAbs(p) {
		return filepath.Clean(p)
	}
	if cwd, err := os.Getwd(); err == nil {
		candidate := filepath.Join(cwd, p)
		if _, err := os.Stat(candidate); err == nil {
			return filepath.Clean(candidate)
		}
	}
	if abs, err := filepath.Abs(p); err == nil {
		return filepath.Clean(abs)
	}
	return filepath.Clean(p)
}

// generateSpeech renders text to a temporary .mp3 using edge-tts (a Python
// neural text-to-speech tool). It returns the path to the generated file; the
// caller is responsible for removing it.
func generateSpeech(ctx context.Context, ttsBin, voice, text, tmpDir string) (string, error) {
	f, err := os.CreateTemp(tmpDir, "wa-mcp-tts-*.mp3")
	if err != nil {
		return "", fmt.Errorf("create temp audio: %w", err)
	}
	name := f.Name()
	_ = f.Close()
	_ = os.Remove(name) // reserve a unique path; edge-tts writes the file itself

	cmd := exec.CommandContext(ctx, ttsBin, "--voice", voice, "--text", text, "--write-media", name)
	out, err := cmd.CombinedOutput()
	if err != nil {
		_ = os.Remove(name)
		return "", fmt.Errorf("tts: %v: %s", err, out)
	}
	return name, nil
}
