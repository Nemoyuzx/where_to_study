import {deadlineMomentBadges,submissionCounts} from './course-domain.js'
import {uiText} from './ui-text.js'

// This layer consumes one cached projection for both day and week. It owns
// neither requests nor courses, and never assigns a deadline a duration.
export default function CalendarDeadlineMarkers({groups,start,end,pixelsPerMinute,courses,onOpen,language}) {
  const badges=deadlineMomentBadges(groups,courses,start,end,pixelsPerMinute)
  return <div className="time-deadline-layer">
    {groups.map(group=><button key={group.key} type="button" className="time-deadline-marker"
      style={{top:`${(group.minute-start)/(end-start)*100}%`}}
      title={`${group.clock}${uiText(language,'（北京时间）',' (Beijing time)')} · ${group.items.slice(0,3).map(item=>item.label).join(' · ')}${group.items.length>3?` · +${group.items.length-3}`:''}`}
      aria-label={`${group.clock}${uiText(language,'（北京时间）',' (Beijing time)')} · ${group.items[0]?.label||''} · ${group.items.length} · ${uiText(language,'课程详情','Course details')}`}
      onClick={event=>{event.stopPropagation();onOpen(group)}} onKeyDown={event=>event.stopPropagation()}>
      <span className="time-deadline-dot" aria-hidden="true"/>
    </button>)}
    {badges.map(badge=><button key={badge.key} type="button" className="time-deadline-badge" style={{top:`${badge.labelTop/((end-start)*pixelsPerMinute)*100}%`}}
      aria-label={`${badge.clock}${uiText(language,'（北京时间）',' (Beijing time)')} · ${badge.items.length} · ${uiText(language,'课程详情','Course details')}`}
      onClick={event=>{event.stopPropagation();onOpen(badge)}} onKeyDown={event=>event.stopPropagation()}>
      {badge.items.some(point=>submissionCounts([point.assignmentItem]).pending>0)?<span className="time-deadline-pending" aria-hidden="true" title={uiText(language,'未提交','Not submitted')}/>:null}
      <span className="time-deadline-caption"><time>{badge.clock}</time> · <bdi>{Array.from(badge.items[0]?.label||'').slice(0,40).join('')}</bdi>{badge.items.length>1?<small> … +{badge.items.length-1}</small>:null}</span>
    </button>)}
  </div>
}
