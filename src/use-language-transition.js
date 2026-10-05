import {useEffect, useRef, useState} from 'react'
import {LanguageTransition} from './language-transition.js'

export function useLanguageTransition({rootRef, apply, currentLanguage, activePage, resolve}) {
  const [overlay,setOverlay] = useState({phase:'idle',revision:0})
  const latest = useRef(null)
  const measured = useRef(null)
  latest.current = {apply,currentLanguage,resolve}
  const owner = useRef(null)
  if (!owner.current) owner.current = new LanguageTransition({
    apply: value => latest.current.apply(value),
    publish:setOverlay,
    reducedMotion: () => window.matchMedia('(prefers-reduced-motion: reduce)').matches,
    layoutReady: target => {
      const root = rootRef.current
      if (!root?.isConnected || root.getAttribute('lang') !== target) return false
      const bounds = root.getBoundingClientRect()
      const card = root.querySelector('.settings-language')?.getBoundingClientRect()
      if (!card || bounds.width <= 0 || bounds.height <= 0 || card.width <= 0 || card.height <= 0) return false
      const sample = [target, bounds.width, bounds.height, card.x, card.y, card.width, card.height].join('|')
      const stable = measured.current === sample
      measured.current = sample
      return stable
    },
  })
  useEffect(() => {
    owner.current.publish = setOverlay
    const media = window.matchMedia('(prefers-reduced-motion: reduce)')
    const finish = () => owner.current.finish()
    const visibility = () => { if(document.hidden) finish() }
    const motion = () => { if(media.matches) finish() }
    document.addEventListener('visibilitychange',visibility)
    window.addEventListener('pagehide',finish)
    window.addEventListener('blur',finish)
    media.addEventListener('change',motion)
    return () => {
      document.removeEventListener('visibilitychange',visibility)
      window.removeEventListener('pagehide',finish)
      window.removeEventListener('blur',finish)
      media.removeEventListener('change',motion)
      // No late state publication during React unmount.
      owner.current.publish = () => {}
      owner.current.finish(false)
    }
  },[])
  useEffect(() => { if(activePage !== 'settings') owner.current.finish() },[activePage])
  return {overlay, cancel: () => owner.current.finish(false),
    request: value => {
      measured.current = null
      owner.current.request(value, latest.current.resolve(value),latest.current.currentLanguage)
    }}
}
