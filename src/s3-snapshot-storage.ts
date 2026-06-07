import {
  S3Client,
  GetObjectCommand,
  PutObjectCommand,
  DeleteObjectsCommand,
  ListObjectsV2Command,
} from '@aws-sdk/client-s3';
import type {
  SnapshotStorage,
  SnapshotLocation,
  Snapshot,
  SnapshotManifest,
} from '@strands-agents/sdk';

// S3-backed implementation of the Strands SnapshotStorage interface, mirroring
// the SDK's bundled FileStorage key layout so SessionManager behaves identically
// — just persisted to S3 (durable, multi-instance) instead of local disk:
//
//   <sessionId>/scopes/<scope>/<scopeId>/snapshots/
//     snapshot_latest.json
//     manifest.json
//     immutable_history/snapshot_<uuid7>.json
//
// The SDK has no AgentCore Memory adapter; its own docs name S3 as the intended
// custom backend. Snapshot IDs are UUID v7 (lexicographic == chronological), so
// listing relies on S3's lexicographic key ordering.

const MANIFEST = 'manifest.json';
const SNAPSHOT_LATEST = 'snapshot_latest.json';
const IMMUTABLE_HISTORY = 'immutable_history';
const SNAPSHOT_REGEX = /snapshot_([\w-]+)\.json$/;
const SCHEMA_VERSION = '1.0';

export class S3SnapshotStorage implements SnapshotStorage {
  private readonly client: S3Client;

  constructor(
    private readonly bucket: string,
    region = process.env.AWS_REGION ?? 'us-east-1',
  ) {
    this.client = new S3Client({ region });
  }

  private scopePrefix(location: SnapshotLocation): string {
    return `${location.sessionId}/scopes/${location.scope}/${location.scopeId}/snapshots`;
  }

  private latestKey(location: SnapshotLocation): string {
    return `${this.scopePrefix(location)}/${SNAPSHOT_LATEST}`;
  }

  private historyKey(location: SnapshotLocation, snapshotId: string): string {
    return `${this.scopePrefix(location)}/${IMMUTABLE_HISTORY}/snapshot_${snapshotId}.json`;
  }

  private manifestKey(location: SnapshotLocation): string {
    return `${this.scopePrefix(location)}/${MANIFEST}`;
  }

  async saveSnapshot(params: {
    location: SnapshotLocation;
    snapshotId: string;
    isLatest: boolean;
    snapshot: Snapshot;
  }): Promise<void> {
    const key = params.isLatest
      ? this.latestKey(params.location)
      : this.historyKey(params.location, params.snapshotId);
    await this.putJSON(key, params.snapshot);
  }

  async loadSnapshot(params: {
    location: SnapshotLocation;
    snapshotId?: string;
  }): Promise<Snapshot | null> {
    const key =
      params.snapshotId === undefined
        ? this.latestKey(params.location)
        : this.historyKey(params.location, params.snapshotId);
    return this.getJSON<Snapshot>(key);
  }

  async listSnapshotIds(params: {
    location: SnapshotLocation;
    limit?: number;
    startAfter?: string;
  }): Promise<string[]> {
    if (params.limit !== undefined && params.limit <= 0) return [];
    const prefix = `${this.scopePrefix(params.location)}/${IMMUTABLE_HISTORY}/`;
    const ids: string[] = [];
    let continuationToken: string | undefined;

    do {
      const res = await this.client.send(
        new ListObjectsV2Command({
          Bucket: this.bucket,
          Prefix: prefix,
          ContinuationToken: continuationToken,
        }),
      );
      for (const obj of res.Contents ?? []) {
        const id = obj.Key?.match(SNAPSHOT_REGEX)?.[1];
        if (id !== undefined) ids.push(id);
      }
      continuationToken = res.IsTruncated ? res.NextContinuationToken : undefined;
    } while (continuationToken);

    // UUID v7 → lexicographic order is chronological.
    ids.sort();
    let result = params.startAfter
      ? ids.filter((id) => id > params.startAfter!)
      : ids;
    if (params.limit !== undefined) result = result.slice(0, params.limit);
    return result;
  }

  async deleteSession(params: { sessionId: string }): Promise<void> {
    const prefix = `${params.sessionId}/`;
    let continuationToken: string | undefined;

    do {
      const listed = await this.client.send(
        new ListObjectsV2Command({
          Bucket: this.bucket,
          Prefix: prefix,
          ContinuationToken: continuationToken,
        }),
      );
      const keys = (listed.Contents ?? [])
        .map((o) => o.Key)
        .filter((k): k is string => k !== undefined);
      if (keys.length > 0) {
        await this.client.send(
          new DeleteObjectsCommand({
            Bucket: this.bucket,
            Delete: { Objects: keys.map((Key) => ({ Key })) },
          }),
        );
      }
      continuationToken = listed.IsTruncated
        ? listed.NextContinuationToken
        : undefined;
    } while (continuationToken);
  }

  async loadManifest(params: {
    location: SnapshotLocation;
  }): Promise<SnapshotManifest> {
    const manifest = await this.getJSON<SnapshotManifest>(
      this.manifestKey(params.location),
    );
    return (
      manifest ?? {
        schemaVersion: SCHEMA_VERSION,
        updatedAt: new Date().toISOString(),
      }
    );
  }

  async saveManifest(params: {
    location: SnapshotLocation;
    manifest: SnapshotManifest;
  }): Promise<void> {
    await this.putJSON(this.manifestKey(params.location), params.manifest);
  }

  private async putJSON(key: string, data: unknown): Promise<void> {
    await this.client.send(
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: key,
        Body: JSON.stringify(data, null, 2),
        ContentType: 'application/json',
      }),
    );
  }

  // Returns null when the object does not exist (matching FileStorage's
  // null-on-ENOENT contract that SessionManager relies on for "no prior state").
  private async getJSON<T>(key: string): Promise<T | null> {
    try {
      const res = await this.client.send(
        new GetObjectCommand({ Bucket: this.bucket, Key: key }),
      );
      const body = await res.Body?.transformToString();
      return body ? (JSON.parse(body) as T) : null;
    } catch (err) {
      if (this.isNotFound(err)) return null;
      throw err;
    }
  }

  private isNotFound(err: unknown): boolean {
    const name = (err as { name?: string })?.name;
    const status = (err as { $metadata?: { httpStatusCode?: number } })?.$metadata
      ?.httpStatusCode;
    return name === 'NoSuchKey' || name === 'NotFound' || status === 404;
  }
}
