import { distance } from './timeline'
import { Tuning } from './tuning'
import type { Coordinate, TimelineStop } from './types'

export interface NameEntry {
  /** 이름을 붙인 머문 곳의 사진. */
  photoIDs: string[]
  /** 그때의 중심. 가까운 다른 머문 곳이 이름을 물려받는 기준. 위치 없는 머문 곳이면 null. */
  coordinate: Coordinate | null
  /** null이면 "이 머문 곳은 물려받지 말고 자동 이름을 쓴다"는 표시. */
  name: string | null
}

/**
 * 사용자가 직접 붙인 장소 이름. 값을 바꾸지 않고 새 값을 돌려준다.
 *
 * 이름은 "그 머문 곳의 사진"에 붙는다. 그래서 사진이 더해져 중심이 움직여도 이름이 유지되고,
 * 한 곳의 이름을 고쳐도 옆 장소는 바뀌지 않는다.
 * 이름을 붙인 적 없는 머문 곳은, 가까이에 이름 붙인 곳이 있으면 그 이름을 물려받는다(다른 날 같은 곳).
 */
export class CustomPlaceNames {
  readonly entries: readonly NameEntry[]
  /** 사진 id → entries 위치. */
  private readonly entryByPhoto = new Map<string, number>()

  constructor(entries: readonly NameEntry[] = []) {
    this.entries = entries
    entries.forEach((entry, position) => {
      for (const id of entry.photoIDs) {
        if (!this.entryByPhoto.has(id)) {
          this.entryByPhoto.set(id, position)
        }
      }
    })
  }

  /** 직접 붙인 이름. 없으면 radius 안에서 가장 가까운 이름 붙인 곳의 이름. 그것도 없으면 null. */
  name(stop: TimelineStop, radius: number = Tuning.stopRadius): string | null {
    const own = this.ownIndex(stop)
    if (own !== null) {
      return this.entries[own].name
    }
    return this.inheritedName(stop, radius, null)
  }

  /** 앞뒤 공백을 뗀 이름을 이 머문 곳에 붙인다. 빈 글자면 직접 붙인 이름을 지워 자동 이름으로 돌아간다. */
  rename(stop: TimelineStop, text: string, radius: number = Tuning.stopRadius): CustomPlaceNames {
    const trimmed = text.trim()
    const own = this.ownIndex(stop)
    let name: string | null = trimmed
    if (trimmed === '') {
      // 지웠는데도 옆 장소 이름을 물려받게 되면, 물려받지 않는다는 표시를 남긴다.
      if (this.inheritedName(stop, radius, own) === null) {
        return own === null ? this : new CustomPlaceNames(this.entries.filter((_, index) => index !== own))
      }
      name = null
    }
    const photoIDs = new Set(stop.photos.map((photo) => photo.id))
    if (own !== null) {
      for (const id of this.entries[own].photoIDs) {
        photoIDs.add(id)
      }
    }
    const entry: NameEntry = { photoIDs: [...photoIDs].sort(), coordinate: stop.center, name }
    return new CustomPlaceNames(
      own === null ? [...this.entries, entry] : this.entries.map((old, index) => (index === own ? entry : old)),
    )
  }

  toJSON(): readonly NameEntry[] {
    return this.entries
  }

  /** 저장했던 값을 되살린다. 모양이 맞지 않는 항목은 버린다. */
  static fromJSON(value: unknown): CustomPlaceNames {
    if (!Array.isArray(value)) {
      return new CustomPlaceNames()
    }
    return new CustomPlaceNames(value.flatMap((item) => (isNameEntry(item) ? [item] : [])))
  }

  /** 이 머문 곳의 사진과 가장 많이 겹치는 항목. 같으면 먼저 만든 항목. */
  private ownIndex(stop: TimelineStop): number | null {
    const overlap = new Map<number, number>()
    for (const photo of stop.photos) {
      const index = this.entryByPhoto.get(photo.id)
      if (index !== undefined) {
        overlap.set(index, (overlap.get(index) ?? 0) + 1)
      }
    }
    let best: number | null = null
    for (const [index, count] of overlap) {
      const bestCount = best === null ? 0 : (overlap.get(best) ?? 0)
      if (count > bestCount || (count === bestCount && best !== null && index < best)) {
        best = index
      }
    }
    return best
  }

  private inheritedName(stop: TimelineStop, radius: number, excluded: number | null): string | null {
    if (!stop.center) {
      return null
    }
    let best: { name: string; distance: number } | null = null
    this.entries.forEach((entry, index) => {
      if (index === excluded || entry.name === null || !entry.coordinate) {
        return
      }
      const meters = distance(stop.center as Coordinate, entry.coordinate)
      if (meters <= radius && meters < (best?.distance ?? Infinity)) {
        best = { name: entry.name, distance: meters }
      }
    })
    return (best as { name: string; distance: number } | null)?.name ?? null
  }
}

function isCoordinate(value: unknown): value is Coordinate {
  if (typeof value !== 'object' || value === null) return false
  const { latitude, longitude } = value as Record<string, unknown>
  return typeof latitude === 'number' && typeof longitude === 'number'
}

function isNameEntry(value: unknown): value is NameEntry {
  if (typeof value !== 'object' || value === null) return false
  const { photoIDs, coordinate, name } = value as Record<string, unknown>
  return (
    Array.isArray(photoIDs) &&
    photoIDs.every((id) => typeof id === 'string') &&
    (coordinate === null || isCoordinate(coordinate)) &&
    (name === null || typeof name === 'string')
  )
}
