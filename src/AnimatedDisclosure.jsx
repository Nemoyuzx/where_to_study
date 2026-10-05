import {useLayoutEffect,useRef} from 'react'

// Retain the actual children/drafts and animate both directions from the
// currently painted height. Reversals cancel only this presentation work.
export default function AnimatedDisclosure({expanded,id,className='',children}) {
  const host=useRef(null),body=useRef(null),work=useRef(null),revision=useRef(0),mounted=useRef(false)
  const initial=useRef({height:expanded?'auto':'0px',opacity:expanded?1:0})
  useLayoutEffect(()=>{
    const node=host.current,content=body.current
    if(!node||!content)return
    const token=++revision.current
    const stop=()=>{
      work.current?.animation?.cancel()
      if(work.current?.frame)cancelAnimationFrame(work.current.frame)
      if(work.current?.timer)clearTimeout(work.current.timer)
      work.current=null;node.style.transition=''
    }
    const finish=()=>{
      if(token!==revision.current)return
      node.style.height=expanded?'auto':'0px';node.style.opacity=expanded?'1':'0'
      stop()
    }
    if(!mounted.current||window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      mounted.current=true;finish();return stop
    }
    const start=node.getBoundingClientRect().height,opacity=getComputedStyle(node).opacity
    stop();node.style.height=`${start}px`;node.style.opacity=opacity
    let target=expanded?content.getBoundingClientRect().height:0
    const animate=(from,alpha)=>{
      if(typeof node.animate==='function') {
        const animation=node.animate([{height:`${from}px`,opacity:alpha},{height:`${target}px`,opacity:expanded?1:0}],
          {duration:220,easing:'cubic-bezier(0.22,0.61,0.36,1)',fill:'forwards'})
        work.current={animation}
        animation.finished.then(()=>{if(work.current?.animation===animation)finish()}).catch(()=>{})
      }else {
        const frame=requestAnimationFrame(()=>{
          if(token!==revision.current)return
          node.style.transition='height 220ms ease, opacity 180ms ease'
          node.style.height=`${target}px`;node.style.opacity=expanded?'1':'0'
          work.current={timer:setTimeout(finish,230)}
        })
        work.current={frame}
      }
    }
    animate(start,opacity)
    const resize=typeof ResizeObserver==='function'?new ResizeObserver(()=>{
      if(!expanded||!work.current||token!==revision.current)return
      const next=content.getBoundingClientRect().height
      if(Math.abs(next-target)<1)return
      const painted=node.getBoundingClientRect().height,alpha=getComputedStyle(node).opacity
      stop();target=next;node.style.height=`${painted}px`;node.style.opacity=alpha;animate(painted,alpha)
    }):null
    resize?.observe(content)
    return ()=>{
      const painted=node.getBoundingClientRect().height,alpha=getComputedStyle(node).opacity
      resize?.disconnect();stop();node.style.height=`${painted}px`;node.style.opacity=alpha
    }
  },[expanded])
  useLayoutEffect(()=>()=>{revision.current++},[])
  return <div ref={host} id={id} className={`animated-disclosure ${className}`} style={initial.current}
    aria-hidden={!expanded} inert={!expanded} data-expanded={expanded}>
    <div ref={body} className="animated-disclosure-body">{children}</div>
  </div>
}
