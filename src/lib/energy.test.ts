import {expect,it} from 'vitest'
import {comparison,energyIntervals,type EnergyReading} from './energy'

function reading(date:string,vt:number,nt:number,priceVt=5,priceNt=3):EnergyReading{
  return {id:date,household_id:'h',reading_date:date,vt_kwh:vt,nt_kwh:nt,price_vt_kwh:priceVt,price_nt_kwh:priceNt,created_at:'',created_by:'a'}
}

it('první odečet je výchozí stav bez vymyšlené spotřeby nebo procenta',()=>{
  const one=[reading('2026-01-01',100,50)]
  expect(energyIntervals(one)[0].interval).toBeNull()
  expect(comparison(one)).toBeNull()
})

it('druhý odečet počítá VT, NT, celkem i cenu za období podle aktuální ceny',()=>{
  const [latest]=energyIntervals([reading('2026-01-01',100,50),reading('2026-02-01',125,60,6,4)])
  expect(latest.interval).toEqual({vt:25,nt:10,total:35,cost:190,days:31})
})

it('porovnání dokončených intervalů a různé délky dní',()=>{
  const readings=[reading('2026-01-01',100,50),reading('2026-02-01',130,70),reading('2026-02-11',145,80)]
  expect(comparison(readings)).toEqual({change:-25,percent:-50,previous:{vt:30,nt:20,total:50,cost:210,days:31}})
  expect(energyIntervals(readings)[0].interval?.days).toBe(10)
})

it('počet dní vychází z kalendářního data i přes změnu letního času',()=>{
  expect(energyIntervals([reading('2026-03-28',0,0),reading('2026-03-30',1,1)])[0].interval?.days).toBe(2)
})

it('nulový předchozí interval nemá zavádějící procento',()=>{
  expect(comparison([reading('2026-01-01',1,1),reading('2026-01-02',1,1),reading('2026-01-03',2,1)])?.percent).toBeNull()
})
