// A bounded presentation transaction, not a data/loading transaction. It holds
// no screenshot, browser cookies, business cache, or historical page tree.
export function createLanguageTransitionFocusGuard({owner, hasFocus,
  schedule = (action,ms) => globalThis.setTimeout(action,ms),
  cancel = id => globalThis.clearTimeout(id)}) {
  let timer = null
  const clear = () => {
    if (timer !== null) cancel(timer)
    timer = null
  }
  return {
    blur() {
      clear()
      if (owner.phase === 'idle') return
      const revision = owner.revision
      // Native select popups can return focus after the cover has committed.
      // Their transient blur must not cancel the readiness/paint transaction.
      timer = schedule(() => {
        timer = null
        if (owner.revision === revision && !hasFocus()) owner.finish()
      },400)
    },
    focus: clear,
    finish() { clear(); owner.finish() },
    dispose: clear,
  }
}

export class LanguageTransition {
  constructor({apply, publish, layoutReady, reducedMotion,
    schedule = (action,ms) => globalThis.setTimeout(action,ms),
    cancel = id => globalThis.clearTimeout(id),
    frame = action => globalThis.requestAnimationFrame(action),
    cancelFrame = id => globalThis.cancelAnimationFrame(id)}) {
    Object.assign(this, {apply, publish, layoutReady, reducedMotion, schedule, cancel, frame, cancelFrame})
    this.revision = 0
    this.timers = new Set()
    this.frames = new Set()
    this.pending = null
    this.target = null
    this.phase = 'idle'
  }

  emit(value) { this.phase=value.phase; this.publish(value) }

  after(ms, revision, action) {
    const id = this.schedule(() => {
      this.timers.delete(id)
      if (revision === this.revision) action()
    }, ms)
    this.timers.add(id)
  }

  nextFrame(revision, action) {
    const id = this.frame(() => {
      this.frames.delete(id)
      if (revision === this.revision) action()
    })
    this.frames.add(id)
  }

  clearWork() {
    for (const id of this.timers) this.cancel(id)
    for (const id of this.frames) this.cancelFrame(id)
    this.timers.clear()
    this.frames.clear()
  }

  request(preference, target, current) {
    this.revision += 1
    this.clearWork()
    this.pending = null
    this.target = null
    const revision = this.revision
    // A reverse choice before commit cancels the pending opposite language.
    if (target === current || this.reducedMotion()) {
      this.apply(preference)
      this.emit({phase:'idle', revision})
      return
    }
    this.pending = preference
    this.target = target
    this.emit({phase:'covering', target, revision})
    this.after(120, revision, () => {
      const value = this.pending
      this.pending = null
      this.emit({phase:'waiting', target, revision})
      this.apply(value)
      const check = () => {
        if (!this.layoutReady(target)) { this.nextFrame(revision, check); return }
        // The first callback observes the target DOM; the next permits a paint.
        this.nextFrame(revision, () => {
          if (this.layoutReady(target)) this.reveal(revision)
          else this.nextFrame(revision, check)
        })
      }
      this.nextFrame(revision, check)
      // Hidden/detached rendering must never leave an indefinite blur curtain.
      // A timeout is cancellation, never evidence of target-language readiness.
      this.after(5000, revision, () => this.finish(false))
    })
  }

  reveal(revision) {
    if (revision !== this.revision || this.target === null) return
    const target = this.target
    this.target = null
    this.clearWork()
    this.emit({phase:'completed',target,revision,completed:true})
    // Ring/check drawing completes before the completion dwell and fade.
    this.after(800, revision, () => {
      this.emit({phase:'revealing', target, revision,completed:true})
      this.after(220, revision, () => this.emit({phase:'idle', revision}))
    })
  }

  finish(commitPending = true, expectedRevision = this.revision) {
    if (expectedRevision !== this.revision) return
    if (this.phase==='idle' && this.pending===null && this.target===null && !this.timers.size && !this.frames.size) return
    this.revision += 1
    this.clearWork()
    const value = this.pending
    this.pending = null
    this.target = null
    if (commitPending && value !== null) this.apply(value)
    this.emit({phase:'idle', revision:this.revision})
  }
}
