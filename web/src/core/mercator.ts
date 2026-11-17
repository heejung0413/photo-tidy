import type { Coordinate } from './types'

/** 지도 타일 한 장의 한 변(픽셀). */
export const TILE_SIZE = 256

export interface Point {
  x: number
  y: number
}

export interface Tile {
  x: number
  y: number
  z: number
  /** 그림 왼쪽 위에서 이 타일의 왼쪽 위까지(픽셀). */
  left: number
  top: number
}

/** 좌표 → 세계 지도 픽셀(웹 메르카토르). 줌 0에서 세계가 256×256이고, 줌이 1 오를 때마다 2배가 된다. */
export function project(coordinate: Coordinate, zoom: number): Point {
  const scale = TILE_SIZE * 2 ** zoom
  const latitude = (coordinate.latitude * Math.PI) / 180
  return {
    x: ((coordinate.longitude + 180) / 360) * scale,
    y: ((1 - Math.log(Math.tan(latitude) + 1 / Math.cos(latitude)) / Math.PI) / 2) * scale,
  }
}

/** 세계 지도 픽셀 → 좌표. */
export function unproject(point: Point, zoom: number): Coordinate {
  const scale = TILE_SIZE * 2 ** zoom
  const n = Math.PI - (2 * Math.PI * point.y) / scale
  return {
    latitude: (Math.atan(Math.sinh(n)) * 180) / Math.PI,
    longitude: (point.x / scale) * 360 - 180,
  }
}

/**
 * 좌표들이 width×height 그림의 여백(padding) 안에 모두 들어가는 가장 큰 줌과 그때의 가운데.
 * 좌표가 없으면 null.
 */
export function fitView(
  coordinates: Coordinate[],
  width: number,
  height: number,
  padding: number,
  maxZoom: number,
): { center: Coordinate; zoom: number } | null {
  if (coordinates.length === 0) {
    return null
  }
  if (coordinates.length === 1) {
    return { center: coordinates[0], zoom: maxZoom }
  }
  for (let zoom = maxZoom; zoom >= 0; zoom -= 1) {
    const points = coordinates.map((coordinate) => project(coordinate, zoom))
    const xs = points.map((point) => point.x)
    const ys = points.map((point) => point.y)
    const [minX, maxX, minY, maxY] = [Math.min(...xs), Math.max(...xs), Math.min(...ys), Math.max(...ys)]
    if (zoom === 0 || (maxX - minX <= width - 2 * padding && maxY - minY <= height - 2 * padding)) {
      return { center: unproject({ x: (minX + maxX) / 2, y: (minY + maxY) / 2 }, zoom), zoom }
    }
  }
  return null
}

/** center를 가운데에 둔 width×height 그림을 덮는 타일들. 세계 지도 밖의 타일은 뺀다. */
export function tilesFor(center: Coordinate, zoom: number, width: number, height: number): Tile[] {
  const middle = project(center, zoom)
  const left = middle.x - width / 2
  const top = middle.y - height / 2
  const count = 2 ** zoom
  const tiles: Tile[] = []
  for (let y = Math.floor(top / TILE_SIZE); y * TILE_SIZE < top + height; y += 1) {
    for (let x = Math.floor(left / TILE_SIZE); x * TILE_SIZE < left + width; x += 1) {
      if (x < 0 || y < 0 || x >= count || y >= count) continue
      tiles.push({ x, y, z: zoom, left: x * TILE_SIZE - left, top: y * TILE_SIZE - top })
    }
  }
  return tiles
}
