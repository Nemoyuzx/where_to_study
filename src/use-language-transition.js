import {useEffect, useRef, useState} from 'react'
import {LanguageTransition} from './language-transition.js'

export function useLanguageTransition({rootRef, apply, currentLanguage, activePage, resolve, ready=()=>true}) {
  const [overlay,setOverlay] = useState({phase:'idle',revision:0})
  const latest = useRef(null)
  const measured = useRef(null)
  const scrollAnchor = useRef(null)
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
        || document.hidden || !document.hasFocus() || document.fonts?.status==='loading') { measured.current=null; return false }
      const bounds = root.getBoundingClientRect()
      const card = root.querySelector('.settings-language')?.getBoundingClientRect()
      if (!card || bounds.width <= 0 || bounds.height <= 0 || card.width <= 0 || card.height <= 0) return false
      // Walk each visible subtree once. Repeated ancestor queries/styles for
      // every label made the native language picker needlessly expensive.
      // Keep only a fingerprint and geometry, never input values/page copies.
      let fingerprint=2166136261,count=0
      const add=value=>{for(const character of String(value))fingerprint=Math.imul(fingerprint^character.codePointAt(0),16777619)>>>0}
      const tags=new Set(['H1','H2','H3','LABEL','BUTTON','SELECT','INPUT','P','SMALL','A','SPAN'])
      const walker=document.createTreeWalker(root,NodeFilter.SHOW_ELEMENT,{acceptNode:element=>{
        if(element.matches('.language-blur-overlay,[hidden],[aria-hidden="true"],[inert]'))return NodeFilter.FILTER_REJECT
        const style=getComputedStyle(element)
        if(style.display==='none'||style.visibility==='hidden')return NodeFilter.FILTER_REJECT
        return tags.has(element.tagName)||element.getAttribute('role')==='dialog'?NodeFilter.FILTER_ACCEPT:NodeFilter.FILTER_SKIP
      }})
      for(let element=walker.nextNode();element;element=walker.nextNode()) {
        const rect=element.getBoundingClientRect()
        if(rect.width<=0||rect.height<=0)continue
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
    let blurTimer
    const finish = () => owner.current.finish()
    // Native select popups can transfer focus briefly while closing. Defer
    // genuine app-background cancellation instead of repainting the picker.
    const blur = () => {
      clearTimeout(blurTimer)
      if(owner.current.phase==='idle')return
      blurTimer=setTimeout(()=>{if(!document.hasFocus())finish()},80)
    }
    const focus = () => { clearTimeout(blurTimer) }
    const visibility = () => { if(document.hidden) finish() }
    const motion = () => { if(media.matches) finish() }
    document.addEventListener('visibilitychange',visibility)
    window.addEventListener('pagehide',finish)
    window.addEventListener('blur',blur)
    window.addEventListener('focus',focus)
    media.addEventListener('change',motion)
    return () => {
      document.removeEventListener('visibilitychange',visibility)
      window.removeEventListener('pagehide',finish)
      window.removeEventListener('blur',blur)
      window.removeEventListener('focus',focus)
      clearTimeout(blurTimer)
      media.removeEventListener('change',motion)
      // No late state publication during React unmount.
      owner.current.publish = () => {}
      owner.current.finish(false)
    }
  },[])
  useEffect(() => { if(activePage !== 'settings') owner.current.finish() },[activePage])
  useEffect(()=>{
    const anchor=scrollAnchor.current
    if(!anchor||overlay.phase!=='waiting')return
    const root=rootRef.current
    const scroll=root?.querySelector('.page-content')
    const picker=root?.querySelector('[data-testid="settings-language-picker"]')
    if(scroll&&picker){
      scroll.scrollLeft=anchor.left;scroll.scrollTop=anchor.top
      if(anchor.focused)picker.focus({preventScroll:true})
    }
  },[currentLanguage,overlay.phase])
  return {overlay, currentRevision: () => owner.current.revision,
    cancel: revision => owner.current.finish(false,revision),
    request: value => {
      measured.current = null
      const root=rootRef.current,scroll=root?.querySelector('.page-content')
      scrollAnchor.current=scroll?{left:scroll.scrollLeft,top:scroll.scrollTop,
        focused:document.activeElement===root.querySelector('[data-testid="settings-language-picker"]')}:null
      owner.current.request(value, latest.current.resolve(value),latest.current.currentLanguage)
    }}
}
