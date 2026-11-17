import { describe, expect, test } from 'vitest'
import { pickPlaceName } from './pickPlaceName'

describe('pickPlaceName', () => {
  test('동 이름이 있으면 동 이름', () => {
    expect(pickPlaceName({ name: '서울숲', address: { suburb: '성수동1가', city: '서울특별시' } })).toBe('성수동1가')
  })

  test('동이 없으면 더 넓은 이름으로 넘어간다', () => {
    expect(pickPlaceName({ address: { borough: '성동구', city: '서울특별시' } })).toBe('성동구')
    expect(pickPlaceName({ address: { city: '서울특별시', country: '대한민국' } })).toBe('서울특별시')
    expect(pickPlaceName({ address: { county: '가평군', state: '경기도' } })).toBe('가평군')
  })

  test('주소가 없으면 장소 이름', () => {
    expect(pickPlaceName({ name: '독도', address: {} })).toBe('독도')
  })

  test('쓸 이름이 없으면 null', () => {
    expect(pickPlaceName({ address: { country: '대한민국' } })).toBeNull()
    expect(pickPlaceName({ error: 'Unable to geocode' })).toBeNull()
    expect(pickPlaceName({ address: { suburb: '   ' } })).toBeNull()
  })

  test('이상한 값이면 null', () => {
    expect(pickPlaceName(null)).toBeNull()
    expect(pickPlaceName('문자열')).toBeNull()
    expect(pickPlaceName({ address: '주소가 글자' })).toBeNull()
    expect(pickPlaceName({ address: { suburb: 3 } })).toBeNull()
  })
})
