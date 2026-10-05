// A bounded presentation transaction, not a data/loading transaction. It holds
// no screenshot, browser cookies, business cache, or historical page tree.
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
  }

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
      this.publish({phase:'idle', revision})
      return
    }
    this.pending = preference
    this.target = target
    this.publish({phase:'covering', target, revision})
    this.after(120, revision, () => {
      const value = this.pending
      this.pending = null
      this.publish({phase:'waiting', target, revision})
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
      this.after(600, revision, () => this.reveal(revision))
    })
  }

  reveal(revision) {
    if (revision !== this.revision || this.target === null) return
    const target = this.target
    this.target = null
    this.clearWork()
    this.after(60, revision, () => {
      this.publish({phase:'revealing', target, revision})
      this.after(220, revision, () => this.publish({phase:'idle', revision}))
    })
  }

  finish(commitPending = true) {
    this.revision += 1
    this.clearWork()
    const value = this.pending
    this.pending = null
    this.target = null
    if (commitPending && value !== null) this.apply(value)
    this.publish({phase:'idle', revision:this.revision})
  }
}
