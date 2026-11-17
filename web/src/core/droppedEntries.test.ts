import { describe, expect, test } from 'vitest'
import { collectFiles, type DroppedEntry } from './droppedEntries'

const file = (name: string): DroppedEntry<string> => ({ kind: 'file', name, file: async () => name })

/** 폴더. 실제 브라우저처럼 내용물을 batch개씩 나눠 주고, 다 주면 빈 목록을 준다. */
function folder(name: string, children: DroppedEntry<string>[], batch = 100): DroppedEntry<string> {
  return {
    kind: 'directory',
    name,
    reader: () => {
      let offset = 0
      return async () => {
        const part = children.slice(offset, offset + batch)
        offset += batch
        return part
      }
    },
  }
}

describe('collectFiles', () => {
  test('파일은 그대로 모은다', async () => {
    expect(await collectFiles([file('a.jpg'), file('b.jpg')])).toEqual(['a.jpg', 'b.jpg'])
  })

  test('폴더 안의 파일을, 폴더 속 폴더까지 모은다', async () => {
    const trip = folder('trip', [folder('day1', [file('1.jpg'), file('2.jpg')]), file('note.txt'), folder('day2', [file('3.jpg')])])
    expect(await collectFiles([trip, file('z.jpg')])).toEqual(['1.jpg', '2.jpg', 'note.txt', '3.jpg', 'z.jpg'])
  })

  test('폴더 내용물이 여러 번에 나뉘어 와도 전부 모은다', async () => {
    const many = Array.from({ length: 250 }, (_, i) => file(`${i}.jpg`))
    expect(await collectFiles([folder('many', many, 100)])).toHaveLength(250)
  })

  test('숨김 파일과 숨김 폴더는 건너뛴다', async () => {
    const trip = folder('trip', [file('.DS_Store'), file('1.jpg'), folder('.thumbnails', [file('x.jpg')])])
    expect(await collectFiles([trip])).toEqual(['1.jpg'])
  })

  test('읽지 못한 파일이나 폴더는 건너뛰고 나머지를 모은다', async () => {
    const broken: DroppedEntry<string> = {
      kind: 'file',
      name: 'broken.jpg',
      file: async () => {
        throw new Error('읽기 실패')
      },
    }
    const locked: DroppedEntry<string> = {
      kind: 'directory',
      name: 'locked',
      reader: () => async () => {
        throw new Error('권한 없음')
      },
    }
    expect(await collectFiles([broken, locked, file('ok.jpg')])).toEqual(['ok.jpg'])
  })

  test('빈 폴더는 빈 목록', async () => {
    expect(await collectFiles([folder('empty', [])])).toEqual([])
  })
})
