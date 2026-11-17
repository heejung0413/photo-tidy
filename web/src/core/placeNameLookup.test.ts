import { describe, expect, test } from 'vitest'
import { placeKey } from './placeKey'
import { PlaceNameLookup } from './placeNameLookup'
import type { Coordinate } from './types'

const palace = { latitude: 37.5796, longitude: 126.977 }
const gangnam = { latitude: 37.4979, longitude: 127.0276 }
const jamsil = { latitude: 37.5133, longitude: 127.1001 }

const tick = () => new Promise<void>((resolve) => setTimeout(resolve, 5))

/** 실제 이름 서비스처럼, 요청이 겹치면 뒤에 온 요청에 답하지 못하는 가짜 서비스. */
function fakeService(names: Record<string, string>) {
  const state = { calls: [] as Coordinate[], overlapped: false, busy: false, names }
  const lookup = async (coordinate: Coordinate) => {
    state.calls.push(coordinate)
    if (state.busy) {
      state.overlapped = true
      return null
    }
    state.busy = true
    await tick()
    state.busy = false
    return state.names[placeKey(coordinate)] ?? null
  }
  return { state, lookup }
}

const allNames = () => ({
  [placeKey(palace)]: '세종로',
  [placeKey(gangnam)]: '역삼동',
  [placeKey(jamsil)]: '잠실동',
})

describe('PlaceNameLookup', () => {
  test('동시에 온 요청을 하나씩 보낸다', async () => {
    const { state, lookup } = fakeService(allNames())
    const names = new PlaceNameLookup({ cache: {}, lookup })

    const result = await Promise.all([names.name(palace), names.name(gangnam), names.name(jamsil)])

    expect(state.overlapped).toBe(false)
    expect(result).toEqual(['세종로', '역삼동', '잠실동'])
  })

  test('같은 곳을 동시에 두 번 물으면 한 번만 묻는다', async () => {
    const { state, lookup } = fakeService(allNames())
    const names = new PlaceNameLookup({ cache: {}, lookup })

    const result = await Promise.all([names.name(palace), names.name(palace)])

    expect(result).toEqual(['세종로', '세종로'])
    expect(state.calls).toHaveLength(1)
  })

  test('기억한 이름은 묻지 않고 돌려준다', async () => {
    const { state, lookup } = fakeService(allNames())
    const names = new PlaceNameLookup({ cache: { [placeKey(palace)]: '경복궁' }, lookup })

    expect(await names.name(palace)).toBe('경복궁')
    expect(names.cachedName(palace)).toBe('경복궁')
    expect(state.calls).toHaveLength(0)
  })

  test('실패는 기억하지 않아 다시 물을 수 있다', async () => {
    const { state, lookup } = fakeService({})
    const names = new PlaceNameLookup({ cache: {}, lookup })

    expect(await names.name(palace)).toBeNull()
    expect(names.cachedName(palace)).toBeNull()

    state.names = allNames()
    expect(await names.name(palace)).toBe('세종로')
  })

  test('서비스가 오류를 던져도 실패로 처리하고 다음 요청을 이어 간다', async () => {
    let first = true
    const names = new PlaceNameLookup({
      cache: {},
      lookup: async () => {
        if (first) {
          first = false
          throw new Error('network')
        }
        return '역삼동'
      },
    })

    expect(await Promise.all([names.name(palace), names.name(gangnam)])).toEqual([null, '역삼동'])
  })

  test('새 이름을 받을 때마다 저장하라고 넘겨준다', async () => {
    const { lookup } = fakeService(allNames())
    const saved: Record<string, string>[] = []
    const names = new PlaceNameLookup({ cache: {}, lookup, onChange: (cache) => saved.push({ ...cache }) })

    await names.name(palace)
    await names.name(palace)

    expect(saved).toEqual([{ [placeKey(palace)]: '세종로' }])
  })

  describe('요청 간격', () => {
    /** 가짜 시계. sleep을 부르면 시간이 그만큼 흐른다. */
    function fakeClock() {
      const clock = { time: 10_000, sleeps: [] as number[] }
      return {
        clock,
        now: () => clock.time,
        sleep: async (ms: number) => {
          clock.sleeps.push(ms)
          clock.time += ms
        },
      }
    }

    test('요청을 시작하는 사이를 최소 간격만큼 띄운다', async () => {
      const { clock, now, sleep } = fakeClock()
      const started: number[] = []
      const names = new PlaceNameLookup({
        cache: {},
        minInterval: 1000,
        now,
        sleep,
        lookup: async () => {
          started.push(clock.time)
          clock.time += 300 // 응답에 0.3초 걸렸다.
          return '이름'
        },
      })

      await Promise.all([names.name(palace), names.name(gangnam), names.name(jamsil)])

      expect(started).toEqual([10_000, 11_000, 12_000])
      expect(clock.sleeps).toEqual([700, 700])
    })

    test('기억한 이름은 기다리지 않는다', async () => {
      const { clock, now, sleep } = fakeClock()
      const names = new PlaceNameLookup({
        cache: { [placeKey(gangnam)]: '역삼동' },
        minInterval: 1000,
        now,
        sleep,
        lookup: async () => '세종로',
      })

      await names.name(palace)
      expect(await names.name(gangnam)).toBe('역삼동')

      expect(clock.sleeps).toEqual([])
    })

    test('간격이 이미 지났으면 기다리지 않는다', async () => {
      const { clock, now, sleep } = fakeClock()
      const names = new PlaceNameLookup({ cache: {}, minInterval: 1000, now, sleep, lookup: async () => '이름' })

      await names.name(palace)
      clock.time += 5000
      await names.name(gangnam)

      expect(clock.sleeps).toEqual([])
    })
  })
})
