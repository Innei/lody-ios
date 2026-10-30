import LodyCore
import UIKit

@MainActor
final class FileDiffFixture {
  private var reads = 0

  var service: FileDiffService {
    FileDiffService(
      diff: { request in Self.diff(request) },
      changes: { [self] _ in try await changes() },
      preview: { _, _, _ in throw FilePreviewFailure(message: String(localized: "diff.toast.previewFailed", bundle: .lody)) },
      readStyle: { nil },
      writeStyle: { _ in }
    )
  }

  private func changes() async throws -> RuntimeContract.WorkspaceChanges {
    reads += 1
    let read = reads
    try await Task.sleep(for: .milliseconds(800))
    if read == 2 { throw DataRuntime.failure("command_failed", "offline fixture") }
    let files: [RuntimeContract.WorkspaceChangesOkFilesItem] = read >= 4 ? [] : [
      .init(path: "src/greeting.ts", add: 1, del: 1, kind: .modified),
      .init(path: "docs/new-guide.md", add: 12, del: 0, kind: .added),
      .init(path: "src/removed.ts", add: 0, del: 5, kind: .deleted),
      .init(path: "assets/image.png"),
    ]
    return .ok(.init(base: "HEAD", files: files))
  }

  private static func diff(_ request: FileDiffRequest) -> RuntimeContract.DiffResult {
    guard request.entryId != nil else {
      return .ok(.init(
        base: .current, path: request.path, old: .init(kind: .text, text: "export const greeting = 'hi';\n"),
        new: .init(kind: .text, text: "export const greeting = 'hello';\n"), add: 1, del: 1
      ))
    }
    let typescript = request.path.hasSuffix(".ts")
    return .ok(.init(
      base: .turn, path: request.path, old: .init(kind: .text, text: typescript ? "" : "a\nb\nc\n"),
      new: .init(kind: .text, text: typescript ? sample : "a\nhello\nc\n"), add: 1, del: 1
    ))
  }

  private static let sample = """
    import { readFileSync } from 'node:fs';
    import { hashPassword } from './auth/password.mjs';
    import pg from 'pg';

    const password = readFileSync(new URL('./.tmp-alice.secret', import.meta.url), 'utf8').trim();
    const hash = await hashPassword(password);
    const client = new pg.Client({ connectionString: process.env.DATABASE_URL });
    await client.connect();
    const r = await client.query(
      `UPDATE auth_account SET password_hash = $1 WHERE email = $2 AND deleted_at IS NULL RETURNING id`,
      [hash, 'alice@test.dev'],
    );
    console.log(r.rowCount, r.rows[0]?.id);
    await client.end();
    """
}
