import { describe, expect, test } from 'vitest'
import { CustomPlaceNames } from './customNames'
import type { TimelineStop } from './types'

/** ids의 사진으로 이뤄진 머문 곳. latitude가 없으면 위치 없음. 위도 0.001도는 약 111m. */
function stop(ids: string | string[], latitude?: number, longitude = 127.0): TimelineStop {
  const coordinate = latitude === undefined ? null : { latitude, longitude }
  return {
    photos: (Array.isArray(ids) ? ids : [ids]).map((id) => ({ id, takenAt: 0, coordinate })),
    center: coordinate,
  }
}

describe('CustomPlaceNames', () => {
  test('처음에는 직접 붙인 이름이 없다', () => {
    expect(new CustomPlaceNames().name(stop('a', 37.5))).toBeNull()
  })

  test('앞뒤 공백을 떼고 저장한다', () => {
    const names = new CustomPlaceNames().rename(stop('a', 37.5), '  우리 카페\n')
    expect(names.name(stop('a', 37.5))).toBe('우리 카페')
  })

  test('rename은 원래 값을 바꾸지 않고 새 값을 돌려준다', () => {
    const before = new CustomPlaceNames()
    const after = before.rename(stop('a', 37.5), '카페')
    expect(before.name(stop('a', 37.5))).toBeNull()
    expect(after.name(stop('a', 37.5))).toBe('카페')
  })

  test('빈 글자로 고치면 직접 붙인 이름을 지운다', () => {
    const names = new CustomPlaceNames().rename(stop('a', 37.5), '우리 카페').rename(stop('a', 37.5), '   ')
    expect(names.name(stop('a', 37.5))).toBeNull()
    expect(names.entries).toEqual([])
  })

  describe('이름은 그 머문 곳의 사진에 붙는다', () => {
    test('사진이 더해져 중심이 멀리 움직여도 이름이 남는다', () => {
      const names = new CustomPlaceNames().rename(stop(['p1', 'p2'], 37.5), '우리 집')
      // 같은 사진 2장 + 새 사진 3장. 중심이 약 130m 옮겨졌다.
      expect(names.name(stop(['p1', 'p2', 'p3', 'p4', 'p5'], 37.5012), 80)).toBe('우리 집')
    })

    test('다시 고치면 같은 항목을 고친다', () => {
      const names = new CustomPlaceNames()
        .rename(stop(['p1', 'p2'], 37.5), '카페')
        .rename(stop(['p1', 'p2', 'p3'], 37.5003), '단골 카페')
      expect(names.entries).toHaveLength(1)
      expect(names.name(stop('p3', 37.5003))).toBe('단골 카페')
    })
  })

  describe('가까운 다른 머문 곳은 이름을 물려받는다', () => {
    test('다른 날 같은 곳', () => {
      const names = new CustomPlaceNames().rename(stop('monday', 37.5), '회사')
      expect(names.name(stop('tuesday', 37.5005), 200)).toBe('회사')
    })

    test('반경 밖이면 물려받지 않는다', () => {
      const names = new CustomPlaceNames().rename(stop('a', 37.5), '회사')
      // 위도 0.003도 ≈ 333m.
      expect(names.name(stop('b', 37.503), 200)).toBeNull()
    })

    test('가장 가까운 곳의 이름을 물려받는다', () => {
      const names = new CustomPlaceNames().rename(stop('a', 37.5), '카페').rename(stop('b', 37.501), '서점')
      expect(names.name(stop('c', 37.5003), 200)).toBe('카페')
      expect(names.name(stop('d', 37.5007), 200)).toBe('서점')
    })

    test('기본 반경은 200m', () => {
      const names = new CustomPlaceNames().rename(stop('a', 37.5), '회사')
      expect(names.name(stop('b', 37.5017))).toBe('회사')
      expect(names.name(stop('c', 37.5019))).toBeNull()
    })
  })

  describe('물려받은 이름을 고쳐도 원래 장소는 그대로', () => {
    test('물려받던 곳에 다른 이름을 붙인다', () => {
      const names = new CustomPlaceNames().rename(stop('a', 37.5), '카페').rename(stop('b', 37.5005), '서점')
      expect(names.name(stop('a', 37.5))).toBe('카페')
      expect(names.name(stop('b', 37.5005))).toBe('서점')
    })

    test('물려받은 이름을 지우면 그 머문 곳만 자동 이름으로 돌아간다', () => {
      const names = new CustomPlaceNames().rename(stop('a', 37.5), '카페').rename(stop('b', 37.5005), '')
      expect(names.name(stop('b', 37.5005))).toBeNull()
      expect(names.name(stop('a', 37.5))).toBe('카페')
    })

    test('"물려받지 않음" 표시는 근처의 다른 머문 곳에 퍼지지 않는다', () => {
      const names = new CustomPlaceNames()
        .rename(stop('a', 37.5), '카페')
        .rename(stop('b', 37.5015), '') // a에서 약 167m: 물려받던 이름을 지움
      // c는 b에서 167m, a에서 333m. 물려받을 이름이 없다.
      expect(names.name(stop('c', 37.503))).toBeNull()
    })

    test('"물려받지 않음" 표시가 더 가까이 있어도, 이름 붙인 곳의 이름을 물려받는다', () => {
      const names = new CustomPlaceNames()
        .rename(stop('a', 37.5), '카페')
        .rename(stop('b', 37.5015), '') // 이름을 지운 곳
      // c는 b에서 약 33m, a에서 약 133m. 가까운 b에는 이름이 없으니 a의 이름을 받는다.
      expect(names.name(stop('c', 37.5012))).toBe('카페')
    })

    test('이름 붙인 적 없는 곳을 지우면 아무것도 저장하지 않는다', () => {
      expect(new CustomPlaceNames().rename(stop('a', 37.5), '  ').entries).toEqual([])
    })
  })

  test('위치 없는 머문 곳은 사진으로만 이름이 붙는다', () => {
    const names = new CustomPlaceNames().rename(stop('a'), '집들이')
    expect(names.name(stop('a'))).toBe('집들이')
    expect(names.name(stop('b'))).toBeNull()
    expect(names.name(stop('c', 37.5))).toBeNull()
  })

  test('JSON으로 저장했다가 되살린다', () => {
    const names = new CustomPlaceNames()
      .rename(stop(['a', 'a2'], 37.5), '우리 카페')
      .rename(stop('b'), '집들이')
      .rename(stop('c', 37.5004), '')
    const restored = CustomPlaceNames.fromJSON(JSON.parse(JSON.stringify(names)))
    expect(restored.entries).toEqual(names.entries)
    expect(restored.name(stop('a2', 37.6))).toBe('우리 카페')
  })

  test('저장된 값이 이상하면 빈 상태로 시작한다', () => {
    expect(CustomPlaceNames.fromJSON('깨진 값').entries).toEqual([])
    expect(CustomPlaceNames.fromJSON([{ name: 3 }, null]).entries).toEqual([])
    expect(CustomPlaceNames.fromJSON(undefined).entries).toEqual([])
  })
})
