/**
 * 떨어뜨린 것 하나. 파일이거나 폴더다.
 * 브라우저의 폴더 읽기 기능을 이 모양으로 감싸서 넘긴다(F는 파일을 나타내는 값).
 */
export type DroppedEntry<F> =
  | { kind: 'file'; name: string; file: () => Promise<F> }
  | {
      kind: 'directory'
      name: string
      /** 내용물을 읽는 함수를 만든다. 부를 때마다 다음 묶음을 주고, 다 주면 빈 목록을 준다. */
      reader: () => () => Promise<DroppedEntry<F>[]>
    }

/**
 * 떨어뜨린 파일과 폴더에서 파일을 전부 모은다. 폴더 속 폴더까지 들어간다.
 * 이름이 점으로 시작하는 숨김 파일·폴더(.DS_Store 등)와 읽지 못한 것은 건너뛴다.
 */
export async function collectFiles<F>(entries: DroppedEntry<F>[]): Promise<F[]> {
  const files: F[] = []
  for (const entry of entries) {
    if (entry.name.startsWith('.')) continue
    try {
      if (entry.kind === 'file') {
        files.push(await entry.file())
        continue
      }
      // 폴더 내용물은 한 번에 다 오지 않는다. 빈 목록이 올 때까지 계속 읽는다.
      const next = entry.reader()
      const children: DroppedEntry<F>[] = []
      for (let part = await next(); part.length > 0; part = await next()) {
        children.push(...part)
      }
      files.push(...(await collectFiles(children)))
    } catch {
      // 읽지 못한 파일이나 폴더는 건너뛴다.
    }
  }
  return files
}
