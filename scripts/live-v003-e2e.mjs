import {createClient} from '@supabase/supabase-js'


const {VITE_SUPABASE_URL:url,VITE_SUPABASE_PUBLISHABLE_KEY:key,E2E_EMAIL_A:emailA,E2E_EMAIL_B:emailB,E2E_PASSWORD_A:passwordA,E2E_PASSWORD_B:passwordB}=process.env
if(!url||!key||!emailA||!emailB||!passwordA||!passwordB)throw new Error('Chybí E2E konfigurace')
const client=()=>createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}})
const a=client(),b=client(),checks=[]
const ok=(name,value,detail='')=>{if(!value)throw new Error(`FAILED: ${name}${detail?` – ${detail}`:''}`);checks.push(name)}
const fail=async(name,promise,expected)=>{const {error}=await promise;ok(name,Boolean(error)&&error.message.includes(expected),error?.message)}
const [la,lb]=await Promise.all([a.auth.signInWithPassword({email:emailA,password:passwordA}),b.auth.signInWithPassword({email:emailB,password:passwordB})])
ok('User A přihlášen',!la.error,la.error?.message);ok('User B přihlášen',!lb.error,lb.error?.message)
console.log('E2E: oba uživatelé přihlášeni')
const suffix=Date.now(),ha=(await a.rpc('create_household',{p_name:`Shopping A ${suffix}`})).data,hb=(await b.rpc('create_household',{p_name:`Shopping B ${suffix}`})).data
ok('oddělené domácnosti vytvořeny',Boolean(ha&&hb))
console.log('E2E: oddělené domácnosti vytvořeny')
const invitation=await a.rpc('create_household_invitation',{p_household_id:ha,p_email:emailB})
ok('pozvánka vytvořena',!invitation.error,invitation.error?.message)
const accepted=await b.rpc('respond_to_household_invitation',{p_token:invitation.data[0].invitation_token,p_accept:true})
ok('User B vstoupil do domácnosti A',!accepted.error,accepted.error?.message)
console.log('E2E: společná domácnost připravena')


const seen=[]
const waitFor=async(name,predicate)=>{const deadline=Date.now()+12000;while(Date.now()<deadline){if(predicate())return ok(name,true);await new Promise(resolve=>setTimeout(resolve,100))}ok(name,false,`received ${seen.length} events: ${seen.map(e=>e.eventType).join(", ")}`)}
const channel=b.channel(`e2e-shopping-${suffix}`).on('postgres_changes',{event:'*',schema:'public',table:'shopping_items',filter:`household_id=eq.${ha}`},payload=>seen.push(payload))
await new Promise((resolve,reject)=>{const timeout=setTimeout(()=>reject(new Error('Realtime připojení se neaktivovalo')),8000);channel.subscribe(status=>{if(status==='SUBSCRIBED'){clearTimeout(timeout);resolve()}})})
console.log('E2E: realtime připojení aktivní')
let item=(await a.rpc('add_shopping_item',{p_household_id:ha,p_id:crypto.randomUUID(),p_name:'Mléko'})).data
console.log('E2E: položka přidána')
await waitFor('realtime přidání A → B',()=>seen.some(e=>e.eventType==='INSERT'))
item=(await b.rpc('mark_shopping_item_bought',{p_item_id:item.id,p_expected_version:item.version})).data
console.log('E2E: položka koupena')
await waitFor('realtime koupení B → A/B',()=>seen.some(e=>e.eventType==='UPDATE'&&e.new.status==='bought'))
item=(await a.rpc('restore_shopping_item',{p_item_id:item.id,p_expected_version:item.version})).data
console.log('E2E: položka vrácena')
item=(await b.rpc('rename_shopping_item',{p_item_id:item.id,p_name:'Plnotučné mléko',p_expected_version:item.version})).data
console.log('E2E: položka přejmenována')
await waitFor('realtime návrat a editace',()=>seen.filter(e=>e.eventType==='UPDATE').length>=3)
item=(await b.rpc('delete_shopping_item',{p_item_id:item.id,p_expected_version:item.version})).data
console.log('E2E: položka odstraněna')
await waitFor('realtime odstranění',()=>seen.some(e=>e.new?.deleted_at))
item=(await a.rpc('undo_delete_shopping_item',{p_item_id:item.id,p_expected_version:item.version})).data
console.log('E2E: odstranění vráceno')
ok('Undo odstranění',!item.deleted_at)


const foreign=(await b.rpc('add_shopping_item',{p_household_id:hb,p_id:crypto.randomUUID(),p_name:'Cizí'})).data
console.log('E2E: cizí kontrolní položka připravena')
ok('A nečte položky B',(await a.from('shopping_items').select('id').eq('household_id',hb)).data.length===0)
await fail('A nevytvoří položku v B',a.rpc('add_shopping_item',{p_household_id:hb,p_id:crypto.randomUUID(),p_name:'Útok'}),'not_household_member')
await fail('A nezmění položku B',a.rpc('rename_shopping_item',{p_item_id:foreign.id,p_name:'Útok',p_expected_version:foreign.version}),'shopping_item_not_available')
await fail('A nekoupí položku B',a.rpc('mark_shopping_item_bought',{p_item_id:foreign.id,p_expected_version:foreign.version}),'shopping_item_not_available')
await fail('A nesmaže položku B',a.rpc('delete_shopping_item',{p_item_id:foreign.id,p_expected_version:foreign.version}),'shopping_item_not_available')
await b.removeChannel(channel)
console.log(JSON.stringify({passed:checks.length,checks,householdA:ha,householdB:hb},null,2))
await Promise.all([a.auth.signOut(),b.auth.signOut()])
process.exit(0)

