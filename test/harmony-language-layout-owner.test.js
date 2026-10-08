import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import vm from 'node:vm'
import test from 'node:test'
import {transformSync} from 'esbuild'

const read=file=>readFileSync(new URL('../native/harmony/entry/src/main/ets/view/'+file,import.meta.url),'utf8').replace(/\r\n?/g,'\n')
const root=read('RootView.ets')

// The incoming thumb/revision/1600ms fixtures are superseded by the production
// picker + full-tree/side-effect-acknowledgement cases in
// harmony-language-motion-contract.test.js. Preserve the incoming lifecycle
// regression here against the current shared QM/language window listener.
function methods(source,start,end){
  const first=source.indexOf(start),last=source.indexOf(end,first)
  assert.ok(first>=0&&last>first)
  return source.slice(first,last)
}

test('current window owner retires language work on background and detaches the exact registered listeners',async()=>{
  const production='class WindowOwner {\n'+methods(root,'  private attachPhoneNavigationAvoidance(','  private reduceLanguageMotion(')+
    '\n}\nglobalThis.WindowOwner=WindowOwner'
  for(const event of ['inactive','hidden']){
    const listeners=new Map(),retired=[],offEvents=[]
    const mainWindow={
      on:(name,callback)=>listeners.set(name,callback),
      off:(name,callback)=>{assert.equal(listeners.get(name),callback);listeners.delete(name);offEvents.push(name)},
    }
    const context=vm.createContext({
      PhoneNavigationLayout:{minimumBottomClearanceVp:28},
      window:{
        AvoidAreaType:{TYPE_NAVIGATION_INDICATOR:'navigation',TYPE_SYSTEM:'system'},
        WindowEventType:{WINDOW_INACTIVE:'inactive',WINDOW_HIDDEN:'hidden',WINDOW_ACTIVE:'active',WINDOW_SHOWN:'shown'},
        getLastWindow:()=>Promise.resolve(mainWindow),
      },
    })
    vm.runInContext(transformSync(production,{loader:'ts',target:'es2022'}).code,context)
    const owner=new context.WindowOwner()
    Object.assign(owner,{
      navigationAvoidanceActive:true,navigationWindow:null,navigationAvoidAreaListener:null,qmWindowListener:null,
      qmPlusSession:{cancelQuietLoginOnBackground(){retired.push('qm')},setLoginForeground(){assert.fail('no foreground event')}},
      cancelLanguageTransition(commitIntent){assert.equal(commitIntent,true);retired.push('language')},
      refreshPhoneNavigationBottomMargin(){},
      getUIContext:()=>({getHostContext:()=>({})}),
    })
    owner.attachPhoneNavigationAvoidance()
    await Promise.resolve()
    assert.equal(listeners.size,2)
    listeners.get('windowEvent')(event)
    assert.deepEqual(retired,['qm','language'])
    owner.detachPhoneNavigationAvoidance()
    assert.equal(listeners.size,0)
    assert.deepEqual(new Set(offEvents),new Set(['windowEvent','avoidAreaChange']))
    assert.equal(owner.navigationWindow,null)
    assert.equal(owner.qmWindowListener,null)
  }
  assert.equal((root.match(/private beginLanguageTransition\(/g)||[]).length,1)
  assert.doesNotMatch(root,/languageWindowEventListener|languageChangeAppliedRevision|settings\.language\.thumb/)
})
