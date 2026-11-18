import { test as base } from '@playwright/test'
import { FakeServices } from './services.ts'
import { TimelinePage } from './timelinePage.ts'

interface Fixtures {
  /** 가짜 지도 타일·장소 이름 응답. 테스트마다 새로 만들어 자동으로 설치한다. */
  services: FakeServices
  /** 가짜 서비스를 설치한 뒤 첫 화면을 연 타임라인 화면. */
  timeline: TimelinePage
}

/**
 * 화면 테스트는 `@playwright/test` 대신 여기서 `test`, `expect`를 가져온다.
 * 테스트가 시작될 때 이미 가짜 서비스가 설치돼 있고 첫 화면이 열려 있다.
 */
export const test = base.extend<Fixtures>({
  services: [
    async ({ page }, use) => {
      const services = new FakeServices()
      await services.install(page)
      await use(services)
    },
    { auto: true },
  ],
  timeline: [
    // services를 받아야 가짜 서비스가 먼저 설치된다.
    async ({ page, services: _services }, use) => {
      await page.goto('/')
      await use(new TimelinePage(page))
    },
    { auto: true },
  ],
})

export { expect } from '@playwright/test'
