// Command wa-mcp is a Model Context Protocol (MCP) server that lets an AI
// agent (e.g. Claude Code) send WhatsApp messages by shelling out to the `wa`
// CLI. Its primary purpose is to let the agent notify / ping a human operator
// when it needs attention or hits a decision only a human can make.
//
// Configuration (all optional, via environment variables):
//
//	WA_BIN    path to the `wa` binary          (default: "wa", looked up on PATH)
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
	waBin := os.Getenv("WA_BIN")
	if waBin == "" {
		waBin = "wa"
	}
	waDir := os.Getenv("WA_DIR")
	if waDir == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return fmt.Errorf("resolve home dir: %w", err)
		}
		waDir = filepath.Join(home, ".claude", "mcp-servers", "whatapp")
	}

	ttsBin := os.Getenv("TTS_BIN")
	if ttsBin == "" {
		venv := filepath.Join(waDir, "tts-venv", "bin", "edge-tts")
		if _, err := os.Stat(venv); err == nil {
			ttsBin = venv
		} else {
			ttsBin = "edge-tts"
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

	sendTool := mcp.NewTool("send_message",
		mcp.WithDescription(
			"Send a WhatsApp message to the operator's watch number. Use this to "+
				"notify/ping the operator when you need their attention, are blocked on a "+
				"decision, or have finished a long-running task."),
		mcp.WithString("message",
			mcp.Required(),
			mcp.Description("The message text to send."),
		),
	)
	s.AddTool(sendTool, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		args, _ := req.Params.Arguments.(map[string]any)

		message, _ := args["message"].(string)
		if message == "" {
			return mcp.NewToolResultError("missing required parameter: message"), nil
		}

		// The `wa` binary bakes in the watch number; it always sends there.
		cmd := exec.CommandContext(ctx, waBin, "send", message)
		cmd.Dir = waDir
		out, err := cmd.CombinedOutput()
		if err != nil {
			return mcp.NewToolResultError(fmt.Sprintf("failed to send: %v: %s", err, out)), nil
		}
		return mcp.NewToolResultText(string(out)), nil
	})

	statusTool := mcp.NewTool("status",
		mcp.WithDescription("Check the WhatsApp login status of the underlying CLI."),
	)
	s.AddTool(statusTool, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		cmd := exec.CommandContext(ctx, waBin, "status")
		cmd.Dir = waDir
		out, err := cmd.CombinedOutput()
		if err != nil {
			return mcp.NewToolResultError(fmt.Sprintf("failed: %v: %s", err, out)), nil
		}
		return mcp.NewToolResultText(string(out)), nil
	})

	callTool := mcp.NewTool("call",
		mcp.WithDescription(
			"Place a WhatsApp voice call to the operator's watch number. The call rings "+
				"for ~30s then hangs up. To speak to the operator, provide `text` (spoken "+
				"via neural text-to-speech) or an `audio` file path to play once answered. "+
				"Use this to escalate when a text ping has gone unanswered."),
		mcp.WithString("text",
			mcp.Description("Optional text to speak. If set, it is rendered to speech (edge-tts) and played when the call is answered. Takes precedence over `audio`."),
		),
		mcp.WithString("audio",
			mcp.Description("Optional path to an audio file (.mp3/.wav/.opus) to play when the call is answered."),
		),
	)
	s.AddTool(callTool, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		args, _ := req.Params.Arguments.(map[string]any)

		audio, _ := args["audio"].(string)
		if text, _ := args["text"].(string); text != "" {
			path, err := generateSpeech(ctx, ttsBin, ttsVoice, text, os.TempDir())
			if err != nil {
				return mcp.NewToolResultError(err.Error()), nil
			}
			defer os.Remove(path)
			audio = path
		}

		cmdArgs := []string{"call"}
		if audio != "" {
			cmdArgs = append(cmdArgs, audio)
		}

		cmd := exec.CommandContext(ctx, waBin, cmdArgs...)
		cmd.Dir = waDir
		out, err := cmd.CombinedOutput()
		if err != nil {
			return mcp.NewToolResultError(fmt.Sprintf("failed to call: %v: %s", err, out)), nil
		}
		return mcp.NewToolResultText(string(out)), nil
	})

	return server.ServeStdio(s)
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
