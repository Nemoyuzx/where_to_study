import {useSyncExternalStore} from 'react'
const empty=Object.freeze({courses:null,assignments:null,fetchedAt:'',cloudBusy:false,cloudError:'',cacheWarning:false,qm:null})
const noSubscribe=()=>()=>{}
const noSnapshot=()=>empty
export function useCourseData(owner) {
  return useSyncExternalStore(owner?.subscribe||noSubscribe,owner?.getSnapshot||noSnapshot,owner?.getSnapshot||noSnapshot)
}
