import { Component, type ErrorInfo, type ReactNode } from "react";

/** Shows a crash instead of a white screen, with a way back. */
export class ErrorBoundary extends Component<{ children: ReactNode }, { error?: Error }> {
  state: { error?: Error } = {};
  static getDerivedStateFromError(error: Error) { return { error }; }
  componentDidCatch(error: Error, info: ErrorInfo) { console.error(error, info.componentStack); }
  render() {
    if (!this.state.error) return this.props.children;
    return (
      <main className="relative z-10 mx-auto max-w-[520px] px-5 pt-10">
        <h1 className="text-[28px] font-light">Something broke</h1>
        <p className="mt-2 text-[14px] text-ink-2">Send this to the developer:</p>
        <pre className="glass p-4 mt-3 text-[12px] whitespace-pre-wrap break-words">{String(this.state.error?.stack ?? this.state.error)}</pre>
        <button type="button" onClick={() => { location.hash = "#/"; location.reload(); }} className="glass-prominent pressable mt-5 h-12 px-6 font-medium">Reload</button>
      </main>
    );
  }
}
