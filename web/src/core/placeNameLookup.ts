import { placeKey } from './placeKey'
import type { Coordinate } from './types'

export interface PlaceNameLookupOptions {
  /** 이미 받아 둔 이름. 열쇠는 placeKey. */
  cache: Record<string, string>
  /** 실제로 이름을 받아 오는 일. 실패하면 null을 주거나 오류를 던진다. */
  lookup: (coordinate: Coordinate) => Promise<string | null>
  /** 새 이름을 받을 때마다 기억한 이름 전체를 넘긴다(저장용). */
  onChange?: (cache: Record<string, string>) => void
  /** 요청을 시작하는 최소 간격(밀리초). 서비스의 요청 수 제한을 지키기 위한 것. */
  minInterval?: number
  now?: () => number
  sleep?: (ms: number) => Promise<void>
}

/**
 * 좌표의 장소 이름을 받아 기억해 둔다.
 * 이름 서비스는 요청이 겹치거나 너무 잦으면 답하지 않으므로, 요청을 한 줄로 세워 하나씩 보낸다.
 */
export class PlaceNameLookup {
  private readonly cache: Record<string, string>
  private readonly lookup: (coordinate: Coordinate) => Promise<string | null>
  private readonly onChange: (cache: Record<string, string>) => void
  private readonly minInterval: number
  private readonly now: () => number
  private readonly sleep: (ms: number) => Promise<void>
  /** 줄의 맨 끝 요청. */
  private last: Promise<void> = Promise.resolve()
  /** 마지막 요청을 시작한 시각. */
  private lastStart: number | null = null

  constructor(options: PlaceNameLookupOptions) {
    this.cache = { ...options.cache }
    this.lookup = options.lookup
    this.onChange = options.onChange ?? (() => {})
    this.minInterval = options.minInterval ?? 0
    this.now = options.now ?? (() => Date.now())
    this.sleep = options.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)))
  }

  /** 이미 받아 둔 이름. 서비스에 묻지 않는다. */
  cachedName(coordinate: Coordinate): string | null {
    return this.cache[placeKey(coordinate)] ?? null
  }

  /** 실패하면 null. 실패는 기억하지 않으므로 다음에 다시 묻는다. */
  name(coordinate: Coordinate): Promise<string | null> {
    const key = placeKey(coordinate)
    const cached = this.cache[key]
    if (cached !== undefined) {
      return Promise.resolve(cached)
    }
    const request = this.last.then(async () => {
      // 줄 서 있는 동안 앞 요청이 같은 곳의 이름을 받았을 수 있다.
      const arrived = this.cache[key]
      if (arrived !== undefined) {
        return arrived
      }
      if (this.lastStart !== null) {
        const wait = this.lastStart + this.minInterval - this.now()
        if (wait > 0) {
          await this.sleep(wait)
        }
      }
      this.lastStart = this.now()
      let name: string | null = null
      try {
        name = await this.lookup(coordinate)
      } catch {
        name = null
      }
      if (name === null) {
        return null
      }
      this.cache[key] = name
      this.onChange(this.cache)
      return name
    })
    this.last = request.then(
      () => {},
      () => {},
    )
    return request
  }
}
