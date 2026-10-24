import { z } from 'zod/v4';

const workspaceId = z.string().min(1);
const sessionId = z.string().min(1);
const blocks = z.array(z.record(z.string(), z.unknown()));

export const BillingEntitlement = z
  .object({
    effectivePlanTier: z.enum(['free', 'plus', 'enterprise']),
    checkoutPending: z.boolean(),
  })
  .meta({ id: 'BillingEntitlement' });

export const QuotaReason = z
  .enum([
    'workspace_payment_required',
    'free_session_limit_reached',
    'free_session_turn_limit_reached',
  ])
  .meta({ id: 'QuotaReason' });

// Absent keeps the session's previous value; a boxed null clears it. The host
// folds a bare JSON null into absent, so the null travels inside the box.
export const ClearableString = z
  .object({ value: z.string().nullable() })
  .meta({ id: 'ClearableString' });

export const CreateSessionParams = z
  .object({
    workspaceId,
    projectId: z.string().optional(),
    sessionId: z.string(),
    machineId: z.string(),
    agentConfigId: z.string(),
    userId: z.string(),
    title: z.string(),
    branch: z.string().optional(),
    billingEntitlement: BillingEntitlement.nullable(),
  })
  .meta({ id: 'CreateSessionParams' });

export const CreatedSession = z
  .object({
    id: z.string(),
    machineId: z.string(),
    title: z.string(),
    status: z.string(),
    archived: z.boolean(),
    pinned: z.boolean(),
    projectId: z.string(),
    createdAt: z.string(),
    cliType: z.string().optional(),
    agentType: z.string().optional(),
  })
  .meta({ id: 'CreatedSession' });

export const CreateSessionResult = z
  .discriminatedUnion('state', [
    z.object({ state: z.literal('created'), session: CreatedSession }),
    z.object({
      state: z.literal('unknown'),
      session: CreatedSession.optional(),
    }),
    z.object({ state: z.literal('rejected'), reason: QuotaReason.optional() }),
  ])
  .meta({ id: 'CreateSessionResult' });

export const DeleteSessionParams = z
  .object({ workspaceId, sessionId, sessionIds: z.array(z.string()) })
  .meta({ id: 'DeleteSessionParams' });

export const DeleteSessionResult = z
  .object({ sessionIds: z.array(z.string()) })
  .meta({ id: 'DeleteSessionResult' });

export const ArchiveSessionParams = z
  .object({ workspaceId, sessionId, archived: z.boolean() })
  .meta({ id: 'ArchiveSessionParams' });

export const PinSessionParams = z
  .object({ workspaceId, sessionId, pinned: z.boolean() })
  .meta({ id: 'PinSessionParams' });

export const MarkSessionReadParams = z
  .object({ workspaceId, sessionId, lastReadAt: z.number() })
  .meta({ id: 'MarkSessionReadParams' });

export const RenameSessionParams = z
  .object({ workspaceId, sessionId, title: z.string() })
  .meta({ id: 'RenameSessionParams' });

export const CheckTurnQuotaParams = z
  .object({ sessionId, billingEntitlement: BillingEntitlement.nullable() })
  .meta({ id: 'CheckTurnQuotaParams' });

export const CheckTurnQuotaResult = z
  .discriminatedUnion('state', [
    z.object({ state: z.literal('allowed') }),
    z.object({ state: z.literal('not_sent'), reason: QuotaReason }),
  ])
  .meta({ id: 'CheckTurnQuotaResult' });

export const SendTurnParams = z
  .object({
    sessionId,
    id: z.string().optional(),
    backgroundTaskId: z.string().min(1).optional(),
    queue: z.boolean().optional(),
    guide: z.boolean().optional(),
    machineId: z.string(),
    userId: z.string().optional(),
    text: z.string(),
    attachmentBlocks: blocks.optional(),
    cliType: z.string().optional(),
    agentType: z.string().optional(),
    resume: z.string().optional(),
    modelId: ClearableString.optional(),
    modeId: z.string().optional(),
    reasoningEffort: ClearableString.optional(),
    reasoningEffortConfigId: z.string().optional(),
    configOptionValues: z.record(z.string(), z.unknown()).optional(),
    billingEntitlement: BillingEntitlement.nullable(),
  })
  .meta({ id: 'SendTurnParams' });

export const SendTurnResult = z
  .discriminatedUnion('state', [
    z.object({
      state: z.literal('not_sent'),
      reason: z.string(),
      id: z.string().optional(),
    }),
    z.object({
      state: z.literal('unknown'),
      id: z.string(),
      reason: z.string().optional(),
    }),
    z.object({
      state: z.literal('uploaded'),
      id: z.string(),
      reason: z.string().optional(),
      awaitingGuide: z.boolean().optional(),
    }),
    z.object({ state: z.literal('queued'), id: z.string() }),
    z.object({ state: z.literal('accepted'), id: z.string() }),
  ])
  .meta({ id: 'SendTurnResult' });

const edit = {
  sessionId,
  expectedUserTurnId: z.string(),
  id: z.string().optional(),
  userId: z.string(),
  billingEntitlement: BillingEntitlement.nullable(),
};

export const EditSessionParams = z
  .discriminatedUnion('action', [
    z.object({ ...edit, action: z.literal('read') }),
    z.object({
      ...edit,
      action: z.literal('send'),
      backgroundTaskId: z.string().min(1).optional(),
      text: z.string().optional(),
      retainedIds: z.array(z.string()).optional(),
      attachmentBlocks: blocks.optional(),
    }),
  ])
  .meta({ id: 'EditSessionParams' });

const stored = {
  editId: z.string(),
  fileName: z.string().optional(),
  mimeType: z.string().optional(),
  sizeBytes: z.number().optional(),
  storageSessionId: z.string().optional(),
};

export const EditAttachment = z
  .discriminatedUnion('type', [
    z.object({
      ...stored,
      type: z.literal('image'),
      imageId: z.string().optional(),
      width: z.number().optional(),
      height: z.number().optional(),
    }),
    z.object({
      ...stored,
      type: z.literal('file'),
      fileId: z.string().optional(),
      sha256: z.string().optional(),
      textPreview: z.boolean().optional(),
      sourcePath: z.string().optional(),
      transport: z.string().optional(),
      machineId: z.string().optional(),
      uploadedAt: z.number().optional(),
    }),
  ])
  .meta({ id: 'EditAttachment' });

export const EditSessionResult = z
  .discriminatedUnion('state', [
    z.object({
      state: z.literal('ready'),
      id: z.string(),
      text: z.string(),
      attachments: z.array(EditAttachment),
    }),
    z.object({ state: z.literal('accepted'), id: z.string() }),
    z.object({ state: z.literal('not_sent'), reason: z.string() }),
    z.object({ state: z.literal('unknown'), reason: z.string().optional() }),
  ])
  .meta({ id: 'EditSessionResult' });

export const ControlTurnParams = z
  .object({
    action: z.enum(['stop', 'steer']),
    sessionId,
    machineId: z.string().min(1),
    turnId: z.string().min(1),
    messageId: z.string().optional(),
    interrupt: z.boolean().optional(),
  })
  .meta({ id: 'ControlTurnParams' });

export const ControlTurnResult = z
  .discriminatedUnion('state', [
    z.object({ state: z.literal('stopped') }),
    z.object({ state: z.literal('applied') }),
    z.object({
      state: z.literal('not_applied'),
      reason: z.string().optional(),
    }),
  ])
  .meta({ id: 'ControlTurnResult' });

export const RespondPermissionParams = z
  .object({
    sessionId,
    entryId: z.string().min(1),
    itemId: z.string().min(1),
    requestId: z.string().min(1),
    optionId: z.string().min(1),
    answers: z.record(z.string(), z.unknown()).optional(),
  })
  .meta({ id: 'RespondPermissionParams' });

export const RespondPermissionResult = z
  .object({ state: z.enum(['accepted', 'stale', 'conflict']) })
  .meta({ id: 'RespondPermissionResult' });

export type BillingEntitlement = z.infer<typeof BillingEntitlement>;
export type CreateSessionResult = z.input<typeof CreateSessionResult>;
export type CheckTurnQuotaResult = z.input<typeof CheckTurnQuotaResult>;
export type SendTurnResult = z.input<typeof SendTurnResult>;
export type EditSessionResult = z.input<typeof EditSessionResult>;
export type ControlTurnResult = z.input<typeof ControlTurnResult>;
