import type { Page } from '@playwright/test'
import { blankPNG } from './samples.ts'

/** 이름 서비스에 온 요청. */
export interface NameQuery {
  latitude: number
  longitude: number
  /** 이 테스트에서 몇 번째 이름 요청인지(1부터). */
  count: number
}

/** 이름 요청에 줄 답. 주소를 주거나, 연결을 끊거나('abort'), 서비스가 거절한 것처럼 상태 코드를 준다. */
export type NameReply = { address: Record<string, string> } | 'abort' | { status: number }

const cors = { 'access-control-allow-origin': '*' }

/**
 * 바깥 서비스(지도 타일, 장소 이름)를 가짜 응답으로 바꾼다. 인터넷 없이도 테스트가 돈다.
 * 상태를 테스트마다 새로 만들기 때문에 테스트끼리 서로 영향을 주지 않는다.
 */
export class FakeServices {
  /** 지도 타일 응답을 늦출 시간(밀리초). */
  tileDelay = 0
  /** 참이면 지도 타일을 하나도 주지 않는다(인터넷이 끊겼거나 타일 서버가 막은 상황). */
  tilesFail = false
  /** 장소 이름 요청이 온 시각. */
  nameRequests: number[] = []
  /** 장소 이름 요청의 내용(온 순서). */
  nameQueries: NameQuery[] = []
  /** 이름 요청에 줄 답. 기본: 남산 근처만 이름을 주고, 나머지는 이름 없는 응답을 준다. */
  nameReply: (query: NameQuery) => NameReply = ({ latitude }) => {
    const address: Record<string, string> = Math.abs(latitude - 37.5512) < 0.001 ? { suburb: '가짜 남산동' } : {}
    return { address }
  }

  async install(page: Page): Promise<void> {
    await page.route('https://tile.openstreetmap.org/**', async (route) => {
      if (this.tilesFail) return route.abort()
      if (this.tileDelay > 0) await new Promise((resolve) => setTimeout(resolve, this.tileDelay))
      await route.fulfill({ contentType: 'image/png', body: blankPNG, headers: cors })
    })
    await page.route('https://nominatim.openstreetmap.org/**', (route) => {
      const url = new URL(route.request().url())
      this.nameRequests.push(Date.now())
      const query: NameQuery = {
        latitude: Number(url.searchParams.get('lat')),
        longitude: Number(url.searchParams.get('lon')),
        count: this.nameRequests.length,
      }
      this.nameQueries.push(query)
      const reply = this.nameReply(query)
      if (reply === 'abort') return route.abort()
      if ('status' in reply) return route.fulfill({ status: reply.status, json: {}, headers: cors })
      return route.fulfill({ json: reply, headers: cors })
    })
  }
}
