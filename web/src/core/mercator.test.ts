import { describe, expect, test } from 'vitest'
import { fitView, project, tilesFor } from './mercator'

const seoul = { latitude: 37.5446, longitude: 127.0559 }
const jamsil = { latitude: 37.5133, longitude: 127.1001 }
const busan = { latitude: 35.1796, longitude: 129.0756 }

describe('project', () => {
  test('위도 0, 경도 0은 세계 지도의 한가운데', () => {
    expect(project({ latitude: 0, longitude: 0 }, 0)).toEqual({ x: 128, y: 128 })
  })

  test('줌이 1 오르면 픽셀이 2배가 된다', () => {
    const low = project(seoul, 10)
    const high = project(seoul, 11)
    expect(high.x).toBeCloseTo(low.x * 2, 6)
    expect(high.y).toBeCloseTo(low.y * 2, 6)
  })

  test('동쪽은 x가 크고, 북쪽은 y가 작다', () => {
    expect(project(jamsil, 12).x).toBeGreaterThan(project(seoul, 12).x)
    expect(project(seoul, 12).y).toBeLessThan(project(busan, 12).y)
  })
})

describe('fitView', () => {
  test('좌표가 하나면 그곳을 가운데에 두고 최대 줌', () => {
    expect(fitView([seoul], 600, 400, 40, 15)).toEqual({ center: seoul, zoom: 15 })
  })

  test('모든 좌표가 여백 안에 들어가는 가장 큰 줌을 고른다', () => {
    const points = [seoul, jamsil, busan]
    const { center, zoom } = fitView(points, 600, 400, 40, 18)!
    const middle = project(center, zoom)
    const inside = (z: number) => {
      const m = project(center, z)
      return points.every((p) => {
        const q = project(p, z)
        return Math.abs(q.x - m.x) <= 300 - 40 && Math.abs(q.y - m.y) <= 200 - 40
      })
    }
    expect(inside(zoom)).toBe(true)
    expect(inside(zoom + 1)).toBe(false)
    // 가운데는 좌표들의 픽셀 범위 한가운데다.
    const xs = points.map((p) => project(p, zoom).x)
    const ys = points.map((p) => project(p, zoom).y)
    expect(middle.x).toBeCloseTo((Math.min(...xs) + Math.max(...xs)) / 2, 3)
    expect(middle.y).toBeCloseTo((Math.min(...ys) + Math.max(...ys)) / 2, 3)
  })

  test('여백이 크면 더 멀리서 본다', () => {
    const points = [seoul, jamsil, busan]
    const tight = fitView(points, 600, 400, 0, 18)!
    const roomy = fitView(points, 600, 400, 180, 18)!
    expect(roomy.zoom).toBeLessThan(tight.zoom)
    // 여백 180이면 세로로 40픽셀 안에 들어가야 한다.
    const ys = points.map((p) => project(p, roomy.zoom).y)
    expect(Math.max(...ys) - Math.min(...ys)).toBeLessThanOrEqual(40)
  })

  test('가까운 좌표들은 최대 줌을 넘지 않는다', () => {
    const near = { latitude: 37.5447, longitude: 127.056 }
    expect(fitView([seoul, near], 600, 400, 40, 16)?.zoom).toBe(16)
  })

  test('좌표가 없으면 null', () => {
    expect(fitView([], 600, 400, 40, 15)).toBeNull()
  })
})

describe('tilesFor', () => {
  test('타일들이 화면 전체를 덮는다', () => {
    const tiles = tilesFor(seoul, 12, 600, 400)
    expect(Math.min(...tiles.map((t) => t.left))).toBeLessThanOrEqual(0)
    expect(Math.min(...tiles.map((t) => t.top))).toBeLessThanOrEqual(0)
    expect(Math.max(...tiles.map((t) => t.left + 256))).toBeGreaterThanOrEqual(600)
    expect(Math.max(...tiles.map((t) => t.top + 256))).toBeGreaterThanOrEqual(400)
    expect(tiles.every((t) => t.z === 12)).toBe(true)
  })

  test('타일 위치는 가운데 좌표의 픽셀과 맞는다', () => {
    const center = project(seoul, 12)
    for (const tile of tilesFor(seoul, 12, 600, 400)) {
      expect(tile.left).toBeCloseTo(tile.x * 256 - center.x + 300, 6)
      expect(tile.top).toBeCloseTo(tile.y * 256 - center.y + 200, 6)
    }
  })

  test('화면에 걸치지 않는 타일은 넣지 않는다', () => {
    for (const tile of tilesFor(seoul, 12, 600, 400)) {
      expect(tile.left).toBeGreaterThan(-256)
      expect(tile.left).toBeLessThan(600)
      expect(tile.top).toBeGreaterThan(-256)
      expect(tile.top).toBeLessThan(400)
    }
  })

  test('세계 지도 밖의 타일은 넣지 않는다', () => {
    const tiles = tilesFor({ latitude: 0, longitude: 0 }, 1, 2000, 2000)
    expect(tiles).toHaveLength(4)
    expect(tiles.every((t) => t.x >= 0 && t.x < 2 && t.y >= 0 && t.y < 2)).toBe(true)
  })
})
