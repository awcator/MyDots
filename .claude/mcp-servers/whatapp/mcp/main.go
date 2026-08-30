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
			"Send a WhatsApp message to the operator's watch number. Use this to "+
				"notify/ping the operator when you need their attention, are blocked on a "+
				"decision, or have finished a long-running task."),
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
			"Send a photo/image file (e.g. PNG, JPG, GIF, WebP) with an optional caption to the operator's watch number via WhatsApp."),
		mcp.WithString("path",
			mcp.Required(),
			mcp.Description("The file path to the image to send."),
		),
		mcp.WithString("caption",
			mcp.Description("Optional caption for the image."),
		),
	)
	s.AddTool(sendImageTool, handleSendImage)

	sendPhotoTool := mcp.NewTool("send_photo",
		mcp.WithDescription(
			"Send a photo/image file (alias for send_image) with an optional caption to the operator's watch number via WhatsApp."),
		mcp.WithString("path",
			mcp.Required(),
			mcp.Description("The file path to the photo/image to send."),
		),
		mcp.WithString("caption",
			mcp.Description("Optional caption for the photo."),
		),
	)
	s.AddTool(sendPhotoTool, handleSendImage)

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
			"Send a document or file attachment (e.g. PDF, log file, text file, zip, code) with an optional caption to the operator's watch number via WhatsApp."),
		mcp.WithString("path",
			mcp.Required(),
			mcp.Description("The file path to the document/file to send as an attachment."),
		),
		mcp.WithString("caption",
			mcp.Description("Optional caption or description for the attachment."),
		),
	)
	s.AddTool(sendFileTool, handleSendFile)

	sendAttachmentTool := mcp.NewTool("send_attachment",
		mcp.WithDescription(
			"Send a document or file attachment (alias for send_file) with an optional caption to the operator's watch number via WhatsApp."),
		mcp.WithString("path",
			mcp.Required(),
			mcp.Description("The file path to the document/attachment to send."),
		),
		mcp.WithString("caption",
			mcp.Description("Optional caption or description for the attachment."),
		),
	)
	s.AddTool(sendAttachmentTool, handleSendFile)

	// 4. call
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
			ttsBin := resolveTTSBin(waDir)
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
		return runWa(ctx, cmdArgs...)
	})

	return server.ServeStdio(s)
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
