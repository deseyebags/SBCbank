export interface Account {
  id: number
  name: string
  email: string
  balance: number
  created_at?: string | null
}

export interface Payment {
  id: number
  account_id: number
  recipient_account_id?: number | null
  amount: number
  status: string
  execution_id?: string | null
  created_at?: string | null
}

export interface LedgerEntry {
  id: number
  description: string
  amount: number
  created_at?: string | null
}

export interface Statement {
  id: number
  account_id: number
  period: string
  created_at?: string | null
}

export type UserRole = "admin" | "user"

export interface AuthSession {
  access_token: string
  token_type: string
  role: UserRole
  account_id: number | null
  display_name: string
}

export interface AuthProfile {
  subject: string
  role: UserRole
  account_id: number | null
}

let authToken: string | null = null

export function setAuthToken(token: string | null): void {
  authToken = token
}

function queryString(params: Record<string, string | number>): string {
  const search = new URLSearchParams()
  Object.entries(params).forEach(([key, value]) => {
    search.set(key, String(value))
  })
  return search.toString()
}

async function http<T>(path: string, options?: RequestInit): Promise<T> {
  const headers = new Headers(options?.headers)
  if (authToken) {
    headers.set("Authorization", `Bearer ${authToken}`)
  }

  if (options?.body && !(options.body instanceof FormData) && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json")
  }

  const response = await fetch(path, {
    ...options,
    headers,
  })

  if (!response.ok) {
    const text = await response.text()
    let errorMessage = text || `Request failed with status ${response.status}`

    try {
      const parsed = JSON.parse(text) as { detail?: string }
      if (parsed.detail) {
        errorMessage = parsed.detail
      }
    } catch {
      // Ignore parse errors and fallback to plain response text.
    }

    throw new Error(errorMessage)
  }
  return (await response.json()) as T
}

export function loginAdmin(username: string, password: string): Promise<AuthSession> {
  return http<AuthSession>("/api/auth/login/admin", {
    method: "POST",
    body: JSON.stringify({ username, password }),
  })
}

export function loginUser(accountId: number, email: string): Promise<AuthSession> {
  return http<AuthSession>("/api/auth/login/user", {
    method: "POST",
    body: JSON.stringify({ account_id: accountId, email }),
  })
}

export function getAuthMe(): Promise<AuthProfile> {
  return http<AuthProfile>("/api/auth/me")
}

export async function listAccounts(): Promise<Account[]> {
  const response = await http<{ accounts: Account[] }>("/api/accounts")
  return response.accounts
}

export function getAccount(accountId: number): Promise<Account> {
  return http<Account>(`/api/accounts/${accountId}`)
}

export function createAccount(name: string, email: string): Promise<Account> {
  return http<Account>(`/api/accounts?${queryString({ name, email })}`, {
    method: "POST",
  })
}

export function creditAccount(accountId: number, amount: number): Promise<{ new_balance: number }> {
  return http<{ new_balance: number }>(
    `/api/accounts/credit?${queryString({ account_id: accountId, amount })}`,
    { method: "POST" },
  )
}

export function debitAccount(accountId: number, amount: number): Promise<{ new_balance: number }> {
  return http<{ new_balance: number }>(
    `/api/accounts/debit?${queryString({ account_id: accountId, amount })}`,
    { method: "POST" },
  )
}

export async function listPayments(): Promise<Payment[]> {
  const response = await http<{ payments: Payment[] }>("/api/payments")
  return response.payments
}

export function createP2PPayment(
  accountId: number,
  recipientId: number,
  amount: number,
): Promise<{ payment_id: number; execution_id: string; status: string; workflow_status: string }> {
  return http<{ payment_id: number; execution_id: string; status: string; workflow_status: string }>(
    `/api/payments/p2p?${queryString({ account_id: accountId, recipient_id: recipientId, amount })}`,
    { method: "POST" },
  )
}

export async function listLedger(): Promise<LedgerEntry[]> {
  const response = await http<{ ledger: LedgerEntry[] }>("/api/ledger")
  return response.ledger
}

export function createLedgerEntry(description: string, amount: number): Promise<LedgerEntry> {
  return http<LedgerEntry>(`/api/ledger?${queryString({ description, amount })}`, {
    method: "POST",
  })
}

export async function listStatements(): Promise<Statement[]> {
  const response = await http<{ statements: Statement[] }>("/api/statements")
  return response.statements
}

export function createStatement(accountId: number, period: string): Promise<Statement> {
  return http<Statement>(`/api/statements?${queryString({ account_id: accountId, period })}`, {
    method: "POST",
  })
}
