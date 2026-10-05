import {useEffect, useRef, useState} from 'react'
import {LanguageTransition} from './language-transition.js'

export function useLanguageTransition({rootRef, apply, currentLanguage, activePage, resolve, ready=()=>true}) {
  const [overlay,setOverlay] = useState({phase:'idle',revision:0})
  const latest = useRef(null)
  const measured = useRef(null)
  latest.current = {apply,currentLanguage,resolve,ready}
  const owner = useRef(null)
  if (!owner.current) owner.current = new LanguageTransition({
    apply: value => latest.current.apply(value),
    publish:setOverlay,
    reducedMotion: () => window.matchMedia('(prefers-reduced-motion: reduce)').matches,
    layoutReady: target => {
      const root = rootRef.current
      if (!root?.isConnected || root.getAttribute('lang') !== target
        || document.documentElement.lang!==target || !latest.current.ready(target)
        || document.fonts?.status==='loading') { measured.current=null; return false }
      const bounds = root.getBoundingClientRect()
      const card = root.querySelector('.settings-language')?.getBoundingClientRect()
      if (!card || bounds.width <= 0 || bounds.height <= 0 || card.width <= 0 || card.height <= 0) return false
      // Measure the complete mounted UI, not just the language picker. Keep
      // only a fingerprint and geometry, never input values or a page copy.
      let fingerprint=2166136261,count=0
      const add=value=>{for(const character of String(value))fingerprint=Math.imul(fingerprint^character.codePointAt(0),16777619)>>>0}
      for(const element of root.querySelectorAll('h1,h2,h3,label,button,select,input,p,small,a,span,[role="dialog"]')) {
        if(element.closest('.language-blur-overlay,[hidden],[aria-hidden="true"],[inert]'))continue
        const rect=element.getBoundingClientRect()
        if(rect.width<=0||rect.height<=0||getComputedStyle(element).visibility==='hidden')continue
        count++
        add([element.tagName,rect.x,rect.y,rect.width,rect.height,element.scrollWidth,element.scrollHeight].join('|'))
        if(!element.matches('input,select'))add(element.textContent)
        add(element.getAttribute('aria-label')||'');add(element.getAttribute('placeholder')||'')
      }
      const sample = [target,root.getAttribute('dir'),bounds.width,bounds.height,card.x,card.y,card.width,card.height,count,fingerprint].join('|')
      const stable=measured.current?.sample===sample?measured.current.frames+1:1
      measured.current={sample,frames:stable}
      return stable>=3
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
  return {overlay, currentRevision: () => owner.current.revision,
    cancel: revision => owner.current.finish(false,revision),
    request: value => {
      measured.current = null
      owner.current.request(value, latest.current.resolve(value),latest.current.currentLanguage)
    }}
}
