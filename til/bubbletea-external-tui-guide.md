# Running External TUIs from Bubble Tea

A guide to executing and managing external terminal applications from Bubble Tea apps in Go.

---

## Table of Contents

1. [Basic External Command Execution](#basic-external-command-execution)
   - [Implementation](#implementation)
   - [Tips](#tips)
2. [Switching Between Bubble Tea and Subprocess](#switching-between-bubble-tea-and-subprocess)
   - [The Challenge](#the-challenge)
   - [Architecture Overview](#architecture-overview)
   - [Full Implementation](#full-implementation)
   - [How It Works](#how-it-works)
   - [Advanced: Real PTY Support](#advanced-real-pty-support)
3. [References](#references)

---

## Basic External Command Execution

When you need to run an external command that requires stdin (like another TUI) from a Bubble Tea app, use `tea.WithInput(os.Stdin)` when initializing the program. This passes raw terminal input directly to the subprocess.

### Implementation

```go
package main

import (
	"os"
	"os/exec"

	tea "github.com/charmbracelet/bubbletea"
)

type model struct{}

func (m model) Init() tea.Cmd {
	cmd := exec.Command("your-tui-command")

	// Wire up standard input/output directly to the subprocess
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	return tea.ExecProcess(cmd, func(err error) tea.Msg {
		return tea.Quit()
	})
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		if msg.Type == tea.KeyCtrlC {
			return m, tea.Quit
		}
	}
	return m, nil
}

func (m model) View() string {
	return "Running external TUI... (Press Ctrl+C to exit Bubble Tea)\n"
}

func main() {
	p := tea.NewProgram(model{})
	if _, err := p.Run(); err != nil {
		os.Exit(1)
	}
}
```

### Tips

- **Terminal Alt Screens**: If your subprocess runs on the alternate screen (like vim or lazygit), `tea.ExecProcess` safely pauses your Bubble Tea UI and restores it when the subprocess terminates.
- **Troubleshooting**: Review the [official repository discussions](https://github.com/charmbracelet/bubbletea) for stdin and process execution issues.
- **Learning Resource**: Check out [Intro to Bubble Tea in Go](https://dev.to/andyhaskell/intro-to-bubble-tea-in-go-21lg) for building interactive terminal interfaces.

---

## Switching Between Bubble Tea and Subprocess

### The Challenge

`tea.ExecProcess` always waits for the process to exit. To achieve a "tab switch" effect without killing the subprocess, you must:

1. Start the subprocess asynchronously
2. Manage its background execution
3. Dynamically swap `os.Stdin` and `os.Stdout` between Bubble Tea and your subprocess
4. Handle terminal raw mode transitions manually

### Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                      Main Process                        │
│  ┌─────────────────┐        ┌─────────────────────────┐ │
│  │   Bubble Tea    │◄──────►│    Subprocess Manager   │ │
│  │       TUI       │        │                         │ │
│  └────────┬────────┘        └────────────┬────────────┘ │
│           │                              │              │
│           ▼                              ▼              │
│  ┌─────────────────┐        ┌─────────────────────────┐ │
│  │  Input Router   │        │   Output Forwarder      │ │
│  │  (monitorGlobal │        │ (forwardSubprocessOutput│ │
│  │    Inputs)      │        │         )               │ │
│  └─────────────────┘        └─────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### Full Implementation

```go
package main

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"sync"
	"syscall"

	tea "github.com/charmbracelet/bubbletea"
	"golang.org/x/term"
)

// UI states
type activeScreen int

const (
	screenBubbleTea activeScreen = iota
	screenSubprocess
)

// Custom messages for screen switching
type switchToSubprocessMsg struct{}
type switchToBubbleTeaMsg struct{}

type model struct {
	currentScreen activeScreen
	subStdin      io.WriteCloser
	subStdout     io.ReadCloser
	subCmd        *exec.Cmd
	teaProgram    *tea.Program
	mu            sync.Mutex
}

func (m *model) Init() tea.Cmd {
	go m.monitorGlobalInputs()
	return nil
}

func (m *model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c":
			return m, tea.Quit
		case "tab":
			return m, func() tea.Msg { return switchToSubprocessMsg{} }
		}

	case switchToSubprocessMsg:
		m.mu.Lock()
		m.currentScreen = screenSubprocess
		m.mu.Unlock()
		m.teaProgram.ReleaseTerminal()
		_ = m.subCmd.Process.Signal(syscall.SIGWINCH)

	case switchToBubbleTeaMsg:
		m.mu.Lock()
		m.currentScreen = screenBubbleTea
		m.mu.Unlock()
		_ = m.teaProgram.RestoreTerminal()
	}
	return m, nil
}

func (m *model) View() string {
	if m.currentScreen == screenSubprocess {
		return ""
	}
	return "\n  === Bubble Tea Main UI ===\n\n  -> Press [Tab] to switch to the Subprocess TUI.\n  -> Press [Ctrl+C] to quit.\n"
}

func (m *model) forwardSubprocessOutput() {
	buf := make([]byte, 1024)
	for {
		n, err := m.subStdout.Read(buf)
		if err != nil {
			return
		}
		m.mu.Lock()
		active := m.currentScreen
		m.mu.Unlock()

		if active == screenSubprocess {
			_, _ = os.Stdout.Write(buf[:n])
		}
	}
}

func (m *model) monitorGlobalInputs() {
	oldState, err := term.MakeRaw(int(os.Stdin.Fd()))
	if err != nil {
		return
	}
	defer func() { _ = term.Restore(int(os.Stdin.Fd()), oldState) }()

	buf := make([]byte, 1)
	for {
		_, err := os.Stdin.Read(buf)
		if err != nil {
			return
		}

		m.mu.Lock()
		active := m.currentScreen
		m.mu.Unlock()

		if active == screenSubprocess {
			// Tab key (ASCII 9) switches back to Bubble Tea
			if buf[0] == 9 {
				m.teaProgram.Send(switchToBubbleTeaMsg{})
				continue
			}
			_, _ = m.subStdin.Write(buf)
		}
	}
}

func main() {
	cmd := exec.Command("top") // Replace with your TUI command

	subStdin, _ := cmd.StdinPipe()
	subStdout, _ := cmd.StdoutPipe()
	cmd.Stderr = os.Stderr

	m := &model{
		currentScreen: screenBubbleTea,
		subStdin:      subStdin,
		subStdout:     subStdout,
		subCmd:        cmd,
	}

	if err := cmd.Start(); err != nil {
		fmt.Printf("Failed to start subprocess: %v\n", err)
		os.Exit(1)
	}

	go m.forwardSubprocessOutput()

	p := tea.NewProgram(m, tea.WithAltScreen())
	m.teaProgram = p

	if _, err := p.Run(); err != nil {
		fmt.Printf("Error: %v\n", err)
	}

	_ = cmd.Process.Signal(syscall.SIGKILL)
}
```

### How It Works

| Component | Purpose |
|-----------|---------|
| `ReleaseTerminal()` | Tells Bubble Tea to stop listening to terminal input and release its grip on terminal configuration |
| `RestoreTerminal()` | Resumes Bubble Tea's terminal management |
| `monitorGlobalInputs()` | Intercepts raw terminal activity and routes keystrokes to the active screen |
| `forwardSubprocessOutput()` | Pipes subprocess output to stdout only when subprocess is active |
| Escape hatch key | Tab (ASCII 9) triggers return to Bubble Tea without sending the key to subprocess |

### Advanced: Real PTY Support

For subprocesses that rely on rich terminal features (mouse support, advanced colors, dynamic sizing like `lazygit` or `htop`), Go's standard `os.Pipe()` is insufficient because it doesn't create a proper virtual terminal.

Use a real Pseudo-Terminal framework like [creack/pty](https://github.com/creack/pty):

```go
import "github.com/creack/pty"

// Instead of cmd.StdinPipe() / cmd.StdoutPipe()
pty, err := pty.Start(cmd)
// Now you have a real terminal with proper sizing, signals, etc.
```

**Benefits of using a PTY:**
- Proper terminal resizing (SIGWINCH handling)
- Mouse support
- Full color/attribute support
- Proper signal handling

---

## References

- [Bubble Tea GitHub Repository](https://github.com/charmbracelet/bubbletea)
- [Bubble Tea Issue #805 - stdin handling](https://github.com/charmbracelet/bubbletea/issues/805)
- [Bubble Tea Issue #860 - process execution](https://github.com/charmbracelet/bubbletea/issues/860)
- [Intro to Bubble Tea in Go](https://dev.to/andyhaskell/intro-to-bubble-tea-in-go-21lg)
- [creack/pty - Pseudo-terminal for Go](https://github.com/creack/pty)