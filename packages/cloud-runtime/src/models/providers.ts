export type ProviderConfig = {
  id: string;
  machineId: string;
  name: string;
  cliType: 'builtin' | 'registry' | 'custom';
  agentType: string;
  env: Record<string, string>;
  prompt?: string;
  customAcp?: { command: string; args?: string[] };
  runtimeOverrides?: {
    codexPath?: string;
    claudeCodeExecutable?: string;
    kimiPath?: string;
    grokPath?: string;
    devinPath?: string;
    piPath?: string;
    piExtensions?: string[];
  };
  codexAuth?:
    | { mode: 'chatgpt'; profileId: string }
    | { mode: 'api-key'; profileId: string; baseUrl: string };
  titleGeneration?: { configOptionValues?: Record<string, string | boolean> };
};

export type ProviderSummary = Pick<
  ProviderConfig,
  'id' | 'machineId' | 'name' | 'cliType' | 'agentType'
> & {
  state:
    | 'configured'
    | 'queued'
    | 'preparing-runtime'
    | 'verifying'
    | 'awaiting-auth'
    | 'failed';
  failureCode?:
    'runtime-unavailable' | 'runtime-install-failed' | 'verification-failed';
  attempt?: number;
  overLimit?: boolean;
};

export type ProviderMachine = {
  id: string;
  name: string;
  readOnly: boolean;
  availability: 'online' | 'offline' | 'unknown';
  capabilities: Record<string, number>;
};

export type ProviderAuthField = {
  id: string;
  type: 'text' | 'secret' | 'select';
  label: string;
  required: boolean;
  defaultValue?: string;
  options?: { value: string; label: string }[];
};

export type ProviderProgress = {
  status: string;
  percent?: number;
  version?: string;
  authorizationUrl?: string;
  userCode?: string;
  acceptsAuthorizationCode?: boolean;
  requiresAuthorizationConsent?: boolean;
  interactionId?: string;
  authMethods?: { id: string; name: string }[];
  form?: { title?: string; fields: ProviderAuthField[] };
};

export type ProviderCapability = {
  authRequired: boolean;
  models: { modelId: string; name: string }[];
  configOptions: {
    id: string;
    name: string;
    type: 'select' | 'boolean';
    currentValue: string | boolean;
    options: { value: string; name: string }[];
  }[];
  providesSessionTitle?: boolean;
};

export type ProviderOperationResult = {
  id: string;
  kind: 'verify' | 'install' | 'authenticate';
  state: 'running' | 'completed' | 'failed' | 'cancelled';
  progress?: ProviderProgress;
  capability?: ProviderCapability;
  error?: string;
};

type Scope = { workspaceId: string; machineId: string };
export type ProviderRequest =
  | { action: 'list'; workspaceId: string }
  | (Scope & {
      action: 'draft';
      cliType: ProviderConfig['cliType'];
      agentType: string;
    })
  | (Scope & { action: 'get'; id: string })
  | (Scope & {
      action: 'save';
      config: ProviderConfig;
      revision?: string;
      queue?: boolean;
    })
  | (Scope & { action: 'delete' | 'retry'; id: string; revision?: string })
  | (Scope & {
      action: 'verify' | 'install' | 'status' | 'authenticate';
      id: string;
    })
  | (Scope & { action: 'poll' | 'cancel'; operationId: string })
  | (Scope & {
      action: 'auth-input';
      operationId: string;
      code?: string;
      input?: {
        action: 'accept' | 'decline' | 'cancel';
        methodId?: string;
        content?: Record<string, string>;
      };
    });

export type ProviderReply = {
  machines?: ProviderMachine[];
  providers?: ProviderSummary[];
  config?: ProviderConfig;
  revision?: string;
  overLimit?: boolean;
  operation?: ProviderOperationResult;
  status?: {
    status: string;
    version?: string;
    current?: string;
    required?: string;
  };
};

export type ProviderService = (
  request: ProviderRequest,
) => Promise<ProviderReply>;
