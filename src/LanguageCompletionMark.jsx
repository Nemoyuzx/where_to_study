// Original UI motion mark: a drawn ring followed by a rounded rising check.
// No platform-branded asset or system-symbol animation is copied.
export default function LanguageCompletionMark() {
  return <svg className="language-completion-mark" viewBox="0 0 64 64" width="64" height="64" aria-hidden="true" focusable="false">
    <circle className="language-completion-ring" cx="32" cy="32" r="24" transform="rotate(-90 32 32)"/>
    <path className="language-completion-check" d="M18 33 L27 41 L45 23"/>
  </svg>
}
