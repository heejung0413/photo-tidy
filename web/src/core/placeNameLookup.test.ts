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
      throw new Error('요청이 겹쳤다')
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
    let online = false
    const names = new PlaceNameLookup({
      cache: {},
      lookup: async () => {
        if (!online) throw new Error('인터넷 없음')
        return '세종로'
      },
    })

    expect(await names.name(palace)).toBeNull()
    expect(names.cachedName(palace)).toBeNull()

    online = true
    expect(await names.name(palace)).toBe('세종로')
  })

  test('이름이 없다는 답을 받은 곳은 답을 받은 곳이다', async () => {
    const { lookup } = fakeService({})
    const names = new PlaceNameLookup({ cache: {}, lookup })
    await names.name(palace)
    expect(names.isUnknown(palace)).toBe(false)
  })

  test('이름이 없다는 답은 기억해서 다시 묻지 않는다', async () => {
    const { state, lookup } = fakeService({})
    const saved: Record<string, string>[] = []
    const names = new PlaceNameLookup({ cache: {}, lookup, onChange: (cache) => saved.push({ ...cache }) })

    expect(await names.name(palace)).toBeNull()
    expect(await names.name(palace)).toBeNull()

    expect(state.calls).toHaveLength(1)
    // 이름이 없다는 것은 저장하지 않는다. 다음에 방문하면 한 번 다시 묻는다.
    expect(saved).toEqual([])
    expect(names.cachedName(palace)).toBeNull()
  })

  describe('서비스가 계속 실패할 때', () => {
    function failing() {
      const state = { time: 0, calls: 0, fail: true }
      const names = new PlaceNameLookup({
        cache: {},
        maxFailures: 3,
        pauseAfterFailures: 60_000,
        now: () => state.time,
        lookup: async () => {
          state.calls += 1
          if (state.fail) throw new Error('막힘')
          return '이름'
        },
      })
      return { state, names }
    }
    const places = Array.from({ length: 8 }, (_, i) => ({ latitude: 37 + i * 0.01, longitude: 127 }))

    test('연달아 세 번 실패하면 쉬는 동안 묻지 않는다', async () => {
      const { state, names } = failing()
      for (const place of places) {
        expect(await names.name(place)).toBeNull()
      }
      expect(state.calls).toBe(3)
    })

    test('쉬는 시간이 지나면 다시 묻는다', async () => {
      const { state, names } = failing()
      for (const place of places.slice(0, 4)) await names.name(place)
      expect(state.calls).toBe(3)

      state.time = 59_999
      await names.name(places[4])
      expect(state.calls).toBe(3)

      state.time = 60_000
      state.fail = false
      expect(await names.name(places[4])).toBe('이름')
      expect(state.calls).toBe(4)
    })

    test('중간에 성공하면 실패 횟수를 다시 센다', async () => {
      const { state, names } = failing()
      await names.name(places[0])
      await names.name(places[1])
      state.fail = false
      await names.name(places[2])
      state.fail = true
      await names.name(places[3])
      await names.name(places[4])
      // 실패 2 + 성공 1 + 실패 2. 아직 쉬지 않는다.
      expect(state.calls).toBe(5)
      await names.name(places[5])
      await names.name(places[6])
      expect(state.calls).toBe(6)
    })

    test('아직 답을 받지 못한 곳인지 알려 준다', async () => {
      const { state, names } = failing()
      expect(names.isUnknown(places[0])).toBe(true)
      await names.name(places[0]) // 실패
      expect(names.isUnknown(places[0])).toBe(true)
      state.fail = false
      await names.name(places[0]) // 이름을 받음
      expect(names.isUnknown(places[0])).toBe(false)
    })

    test('쉬는 동안에도 기억한 이름은 돌려준다', async () => {
      const { state, names } = failing()
      state.fail = false
      await names.name(places[0])
      state.fail = true
      for (const place of places.slice(1, 5)) await names.name(place)
      expect(await names.name(places[0])).toBe('이름')
    })
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
