import {
  useCallback,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import {
  Navigate,
  NavLink,
  Route,
  Routes,
  useNavigate,
} from "react-router-dom";
import {
  ArrowLeftRight,
  BookOpenText,
  FileText,
  Landmark,
  LogOut,
  RefreshCw,
  ShieldCheck,
  UserRound,
  Wallet,
} from "lucide-react";

import {
  createAccount,
  createLedgerEntry,
  createP2PPayment,
  createStatement,
  creditAccount,
  debitAccount,
  getAccount,
  getAuthMe,
  listAccounts,
  listLedger,
  listPayments,
  listStatements,
  loginAdmin,
  loginUser,
  signUpUser,
  setAuthToken,
  type Account,
  type AuthSession,
  type LedgerEntry,
  type Payment,
  type Statement,
  type UserRole,
} from "@/lib/api";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";

const SESSION_STORAGE_KEY = "sbcbank.auth.session";

type Notice = {
  kind: "success" | "error" | "info";
  text: string;
};

type BadgeVariant = "default" | "success" | "warning" | "danger";
type LoginMode = "admin" | "user";

function roleHome(role: UserRole): string {
  return role === "admin" ? "/admin" : "/app";
}

function paymentStatusVariant(status: string): BadgeVariant {
  const normalized = status.toUpperCase();
  if (normalized === "SUCCESS" || normalized === "COMPLETED") {
    return "success";
  }
  if (normalized === "PENDING" || normalized === "RUNNING") {
    return "warning";
  }
  if (normalized === "FAILED") {
    return "danger";
  }
  return "default";
}

function toErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message : "Unexpected error";
}

function loadStoredSession(): AuthSession | null {
  const raw = window.localStorage.getItem(SESSION_STORAGE_KEY);
  if (!raw) {
    return null;
  }

  try {
    const parsed = JSON.parse(raw) as AuthSession;
    if (
      !parsed.access_token ||
      !parsed.role ||
      (parsed.role !== "admin" && parsed.role !== "user")
    ) {
      return null;
    }

    return {
      ...parsed,
      account_id: parsed.account_id ?? null,
    };
  } catch {
    return null;
  }
}

function persistSession(session: AuthSession | null): void {
  if (!session) {
    window.localStorage.removeItem(SESSION_STORAGE_KEY);
    return;
  }

  window.localStorage.setItem(SESSION_STORAGE_KEY, JSON.stringify(session));
}

function RoleRouteGuard({
  session,
  requiredRole,
  children,
}: {
  session: AuthSession | null;
  requiredRole: UserRole;
  children: ReactNode;
}) {
  if (!session) {
    return <Navigate to="/login" replace />;
  }

  if (session.role !== requiredRole) {
    return <Navigate to={roleHome(session.role)} replace />;
  }

  return <>{children}</>;
}

function LoginPage({
  session,
  onLogin,
}: {
  session: AuthSession | null;
  onLogin: (nextSession: AuthSession) => void;
}) {
  const [mode, setMode] = useState<LoginMode>("admin");
  const [notice, setNotice] = useState<Notice | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const [adminUsername, setAdminUsername] = useState("admin");
  const [adminPassword, setAdminPassword] = useState("admin123");

  const [userAccountId, setUserAccountId] = useState("");
  const [userEmail, setUserEmail] = useState("");
  const [signUpName, setSignUpName] = useState("");
  const [signUpEmail, setSignUpEmail] = useState("");

  if (session) {
    return <Navigate to={roleHome(session.role)} replace />;
  }

  async function handleAdminSignIn() {
    if (!adminUsername.trim() || !adminPassword.trim()) {
      setNotice({
        kind: "error",
        text: "Provide admin username and password.",
      });
      return;
    }

    setIsSubmitting(true);
    try {
      const authSession = await loginAdmin(adminUsername.trim(), adminPassword);
      setAuthToken(authSession.access_token);
      await getAuthMe();
      onLogin(authSession);
    } catch (error) {
      setAuthToken(null);
      setNotice({ kind: "error", text: toErrorMessage(error) });
    } finally {
      setIsSubmitting(false);
    }
  }

  async function handleUserSignIn() {
    const accountId = Number(userAccountId);
    if (!accountId || !userEmail.trim()) {
      setNotice({ kind: "error", text: "Provide account ID and email." });
      return;
    }

    setIsSubmitting(true);
    try {
      const authSession = await loginUser(accountId, userEmail.trim());
      setAuthToken(authSession.access_token);
      await getAuthMe();
      onLogin(authSession);
    } catch (error) {
      setAuthToken(null);
      setNotice({ kind: "error", text: toErrorMessage(error) });
    } finally {
      setIsSubmitting(false);
    }
  }

  async function handleUserSignUp() {
    if (!signUpName.trim() || !signUpEmail.trim()) {
      setNotice({ kind: "error", text: "Provide name and email to sign up." });
      return;
    }

    setIsSubmitting(true);
    try {
      const account = await signUpUser(signUpName.trim(), signUpEmail.trim());
      setSignUpName("");
      setSignUpEmail("");
      setUserAccountId(String(account.id));
      setUserEmail(account.email);
      setNotice({
        kind: "success",
        text: `Account created. Your account ID is ${account.id}. You can now sign in as user.`,
      });
    } catch (error) {
      setNotice({ kind: "error", text: toErrorMessage(error) });
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <main className="min-h-screen px-4 py-10 sm:px-8">
      <section className="mx-auto max-w-5xl">
        <header className="mb-6 text-center">
          <p className="text-xs font-semibold uppercase tracking-[0.22em] text-[var(--text-2)]">
            SC bank Local Console
          </p>
          <h1 className="font-display mt-3 text-4xl font-extrabold tracking-tight text-[var(--text-0)] sm:text-5xl">
            Authentication Gateway
          </h1>
          <p className="mx-auto mt-3 max-w-2xl text-sm text-[var(--text-2)] sm:text-base">
            Sign in as an admin for platform operations, or as a user bound to a
            specific account.
          </p>
        </header>

        {notice && (
          <div
            className={
              "mb-4 rounded-lg border px-4 py-3 text-sm " +
              (notice.kind === "success"
                ? "border-emerald-300 bg-emerald-50 text-emerald-800"
                : notice.kind === "error"
                  ? "border-rose-300 bg-rose-50 text-rose-800"
                  : "border-sky-300 bg-sky-50 text-sky-800")
            }
          >
            {notice.text}
          </div>
        )}

        <div className="grid grid-cols-1 gap-5 lg:grid-cols-2">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <ShieldCheck className="h-5 w-5" /> Role Selection
              </CardTitle>
              <CardDescription>
                Choose your login mode. Authorisation is enforced by backend
                services.
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-3">
              <button
                type="button"
                className={
                  "flex w-full items-center justify-between rounded-lg border px-4 py-3 text-left transition-colors " +
                  (mode === "admin"
                    ? "border-[var(--brand-500)] bg-[var(--brand-100)]"
                    : "border-[var(--border-1)] bg-[var(--surface-2)]")
                }
                onClick={() => setMode("admin")}
              >
                <span className="flex items-center gap-2 font-semibold text-[var(--text-0)]">
                  <ShieldCheck className="h-4 w-4" /> Admin
                </span>
                <span className="text-xs text-[var(--text-2)]">
                  Manage all accounts/services
                </span>
              </button>

              <button
                type="button"
                className={
                  "flex w-full items-center justify-between rounded-lg border px-4 py-3 text-left transition-colors " +
                  (mode === "user"
                    ? "border-[var(--brand-500)] bg-[var(--brand-100)]"
                    : "border-[var(--border-1)] bg-[var(--surface-2)]")
                }
                onClick={() => setMode("user")}
              >
                <span className="flex items-center gap-2 font-semibold text-[var(--text-0)]">
                  <UserRound className="h-4 w-4" /> User
                </span>
                <span className="text-xs text-[var(--text-2)]">
                  Limited to one account
                </span>
              </button>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                {mode === "admin" ? (
                  <ShieldCheck className="h-5 w-5" />
                ) : (
                  <UserRound className="h-5 w-5" />
                )}
                {mode === "admin" ? "Admin Sign In" : "User Sign In"}
              </CardTitle>
              <CardDescription>
                {mode === "admin"
                  ? "Default local credentials are admin / admin123."
                  : "Sign in with account ID and email, or create a new account."}
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-3">
              {mode === "admin" ? (
                <>
                  <Input
                    placeholder="Admin username"
                    value={adminUsername}
                    onChange={(event) => setAdminUsername(event.target.value)}
                  />
                  <Input
                    placeholder="Admin password"
                    type="password"
                    value={adminPassword}
                    onChange={(event) => setAdminPassword(event.target.value)}
                  />
                  <Button
                    className="w-full"
                    onClick={() => void handleAdminSignIn()}
                    disabled={isSubmitting}
                  >
                    {isSubmitting ? "Signing In..." : "Sign In as Admin"}
                  </Button>
                </>
              ) : (
                <>
                  <Input
                    placeholder="Account ID"
                    type="number"
                    value={userAccountId}
                    onChange={(event) => setUserAccountId(event.target.value)}
                  />
                  <Input
                    placeholder="Account email"
                    value={userEmail}
                    onChange={(event) => setUserEmail(event.target.value)}
                  />
                  <Button
                    className="w-full"
                    onClick={() => void handleUserSignIn()}
                    disabled={isSubmitting}
                  >
                    {isSubmitting ? "Signing In..." : "Sign In as User"}
                  </Button>

                  <div className="my-2 border-t border-[var(--border-1)]" />

                  <p className="text-xs font-semibold uppercase tracking-wide text-[var(--text-2)]">
                    New user sign up
                  </p>
                  <Input
                    placeholder="Full name"
                    value={signUpName}
                    onChange={(event) => setSignUpName(event.target.value)}
                  />
                  <Input
                    placeholder="Email"
                    value={signUpEmail}
                    onChange={(event) => setSignUpEmail(event.target.value)}
                  />
                  <Button
                    className="w-full"
                    variant="secondary"
                    onClick={() => void handleUserSignUp()}
                    disabled={isSubmitting}
                  >
                    {isSubmitting ? "Creating Account..." : "Sign Up as New User"}
                  </Button>
                </>
              )}
            </CardContent>
          </Card>
        </div>
      </section>
    </main>
  );
}

function Workspace({
  session,
  onLogout,
}: {
  session: AuthSession;
  onLogout: () => void;
}) {
  const role = session.role;

  const [accounts, setAccounts] = useState<Account[]>([]);
  const [payments, setPayments] = useState<Payment[]>([]);
  const [ledgerEntries, setLedgerEntries] = useState<LedgerEntry[]>([]);
  const [statements, setStatements] = useState<Statement[]>([]);

  const [notice, setNotice] = useState<Notice | null>(null);
  const [isRefreshing, setIsRefreshing] = useState(false);

  const [accountName, setAccountName] = useState("");
  const [accountEmail, setAccountEmail] = useState("");
  const [balanceAccountId, setBalanceAccountId] = useState("");
  const [balanceAmount, setBalanceAmount] = useState("");

  const [payerId, setPayerId] = useState("");
  const [recipientId, setRecipientId] = useState("");
  const [paymentAmount, setPaymentAmount] = useState("");

  const [ledgerDescription, setLedgerDescription] = useState("");
  const [ledgerAmount, setLedgerAmount] = useState("");

  const [statementAccountId, setStatementAccountId] = useState("");
  const [statementPeriod, setStatementPeriod] = useState("");

  const [userRecipientId, setUserRecipientId] = useState("");
  const [userPaymentAmount, setUserPaymentAmount] = useState("");
  const [userStatementPeriod, setUserStatementPeriod] = useState("");
  const [userTopUpAmount, setUserTopUpAmount] = useState("");

  const totalBalance = useMemo(
    () =>
      accounts.reduce((sum, account) => sum + Number(account.balance || 0), 0),
    [accounts],
  );

  const selectedUserAccountId =
    role === "user" && session.account_id ? Number(session.account_id) : null;

  const activeUserAccount = useMemo(() => {
    if (!selectedUserAccountId) {
      return null;
    }
    return (
      accounts.find((account) => account.id === selectedUserAccountId) ?? null
    );
  }, [accounts, selectedUserAccountId]);

  const userPayments = useMemo(() => {
    if (!selectedUserAccountId) {
      return [];
    }
    return payments.filter(
      (payment) =>
        payment.account_id === selectedUserAccountId ||
        payment.recipient_account_id === selectedUserAccountId,
    );
  }, [payments, selectedUserAccountId]);

  const userStatements = useMemo(() => {
    if (!selectedUserAccountId) {
      return [];
    }
    return statements.filter(
      (statement) => statement.account_id === selectedUserAccountId,
    );
  }, [statements, selectedUserAccountId]);

  const refreshAll = useCallback(async () => {
    setIsRefreshing(true);
    try {
      if (role === "admin") {
        const [accountsResult, paymentsResult, ledgerResult, statementsResult] =
          await Promise.all([
            listAccounts(),
            listPayments(),
            listLedger(),
            listStatements(),
          ]);

        setAccounts(accountsResult);
        setPayments(paymentsResult);
        setLedgerEntries(ledgerResult);
        setStatements(statementsResult);
      } else {
        if (!selectedUserAccountId) {
          throw new Error("User session is missing account access");
        }

        const [accountResult, paymentsResult, statementsResult] =
          await Promise.all([
            getAccount(selectedUserAccountId),
            listPayments(),
            listStatements(),
          ]);

        setAccounts([accountResult]);
        setPayments(paymentsResult);
        setLedgerEntries([]);
        setStatements(statementsResult);
      }
    } catch (error) {
      setNotice({ kind: "error", text: toErrorMessage(error) });
    } finally {
      setIsRefreshing(false);
    }
  }, [role, selectedUserAccountId]);

  useEffect(() => {
    void refreshAll();
  }, [refreshAll]);

  async function handleCreateAccount() {
    if (!accountName.trim() || !accountEmail.trim()) {
      setNotice({ kind: "error", text: "Name and email are required." });
      return;
    }

    try {
      await createAccount(accountName.trim(), accountEmail.trim());
      setAccountName("");
      setAccountEmail("");
      setNotice({ kind: "success", text: "Account created." });
      await refreshAll();
    } catch (error) {
      setNotice({ kind: "error", text: toErrorMessage(error) });
    }
  }

  async function handleBalanceUpdate(mode: "credit" | "debit") {
    const accountId = Number(balanceAccountId);
    const amount = Number(balanceAmount);

    if (!accountId || !amount || amount <= 0) {
      setNotice({
        kind: "error",
        text: "Provide valid account ID and amount.",
      });
      return;
    }

    try {
      if (mode === "credit") {
        await creditAccount(accountId, amount);
      } else {
        await debitAccount(accountId, amount);
      }
      setNotice({ kind: "success", text: `Balance ${mode} completed.` });
      await refreshAll();
    } catch (error) {
      setNotice({ kind: "error", text: toErrorMessage(error) });
    }
  }

  async function handleCreatePayment() {
    const payer = Number(payerId);
    const recipient = Number(recipientId);
    const amount = Number(paymentAmount);

    if (!payer || !recipient || !amount || amount <= 0) {
      setNotice({
        kind: "error",
        text: "Provide valid payer, recipient, and amount.",
      });
      return;
    }

    try {
      const result = await createP2PPayment(payer, recipient, amount);
      setNotice({
        kind: "success",
        text: `Payment ${result.payment_id} processed with status ${result.status}.`,
      });
      setPayerId("");
      setRecipientId("");
      setPaymentAmount("");
      await refreshAll();
    } catch (error) {
      setNotice({ kind: "error", text: toErrorMessage(error) });
    }
  }

  async function handleCreateLedgerEntry() {
    const amount = Number(ledgerAmount);
    if (!ledgerDescription.trim() || !amount) {
      setNotice({
        kind: "error",
        text: "Provide ledger description and amount.",
      });
      return;
    }

    try {
      await createLedgerEntry(ledgerDescription.trim(), amount);
      setLedgerDescription("");
      setLedgerAmount("");
      setNotice({ kind: "success", text: "Ledger entry recorded." });
      await refreshAll();
    } catch (error) {
      setNotice({ kind: "error", text: toErrorMessage(error) });
    }
  }

  async function handleCreateStatement() {
    const accountId = Number(statementAccountId);
    if (!accountId || !statementPeriod.trim()) {
      setNotice({
        kind: "error",
        text: "Provide account ID and period (YYYY-MM).",
      });
      return;
    }

    try {
      await createStatement(accountId, statementPeriod.trim());
      setStatementAccountId("");
      setStatementPeriod("");
      setNotice({ kind: "success", text: "Statement generated." });
      await refreshAll();
    } catch (error) {
      setNotice({ kind: "error", text: toErrorMessage(error) });
    }
  }

  async function handleUserPayment() {
    const payer = Number(selectedUserAccountId);
    const recipient = Number(userRecipientId);
    const amount = Number(userPaymentAmount);

    if (!payer || !recipient || !amount || amount <= 0) {
      setNotice({
        kind: "error",
        text: "Provide a valid recipient and amount.",
      });
      return;
    }

    try {
      const result = await createP2PPayment(payer, recipient, amount);
      setNotice({
        kind: "success",
        text: `Payment ${result.payment_id} processed with status ${result.status}.`,
      });
      setUserRecipientId("");
      setUserPaymentAmount("");
      await refreshAll();
    } catch (error) {
      setNotice({ kind: "error", text: toErrorMessage(error) });
    }
  }

  async function handleUserStatement() {
    const accountId = Number(selectedUserAccountId);
    if (!accountId || !userStatementPeriod.trim()) {
      setNotice({ kind: "error", text: "Provide period (YYYY-MM)." });
      return;
    }

    try {
      await createStatement(accountId, userStatementPeriod.trim());
      setUserStatementPeriod("");
      setNotice({ kind: "success", text: "Statement generated." });
      await refreshAll();
    } catch (error) {
      setNotice({ kind: "error", text: toErrorMessage(error) });
    }
  }

  async function handleUserTopUp() {
    const accountId = Number(selectedUserAccountId);
    const amount = Number(userTopUpAmount);

    if (!accountId || !amount || amount <= 0) {
      setNotice({ kind: "error", text: "Provide a valid top-up amount." });
      return;
    }

    try {
      await creditAccount(accountId, amount);
      setUserTopUpAmount("");
      setNotice({ kind: "success", text: "Top up completed." });
      await refreshAll();
    } catch (error) {
      setNotice({ kind: "error", text: toErrorMessage(error) });
    }
  }

  return (
    <main className="min-h-screen px-4 py-6 sm:px-8 sm:py-8">
      <section className="mx-auto w-full max-w-7xl space-y-6">
        <header className="rounded-2xl border border-[var(--border-1)] bg-[var(--surface-1)] p-6 shadow-[0_12px_40px_rgba(12,22,40,0.1)] sm:p-8">
          <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.22em] text-[var(--text-2)]">
                SC bank Local Console
              </p>
              <h1 className="font-display mt-2 text-3xl font-extrabold tracking-tight text-[var(--text-0)] sm:text-5xl">
                {role === "admin"
                  ? "Admin Operations Hub"
                  : "Customer Banking Hub"}
              </h1>
              <p className="mt-2 max-w-2xl text-sm text-[var(--text-2)] sm:text-base">
                {role === "admin"
                  ? "Manage accounts, payments, ledger, and statements across the full platform."
                  : "Send payments and manage statements for your authenticated account."}
              </p>
            </div>

            <div className="flex flex-col items-start gap-3 sm:items-end">
              <div className="flex items-center gap-2">
                <Badge variant="default">Docker Runtime</Badge>
                <Badge variant={role === "admin" ? "warning" : "success"}>
                  {role === "admin" ? "Admin Session" : "User Session"}
                </Badge>
              </div>

              <div className="flex flex-wrap items-center gap-2">
                <NavLink
                  to={roleHome(role)}
                  className="rounded-md border border-[var(--border-1)] bg-[var(--surface-2)] px-3 py-2 text-xs font-semibold uppercase tracking-wide text-[var(--text-1)]"
                >
                  {role === "admin" ? "Admin View" : "User View"}
                </NavLink>
                <Button
                  variant="secondary"
                  onClick={() => void refreshAll()}
                  disabled={isRefreshing}
                >
                  <RefreshCw
                    className={
                      isRefreshing ? "h-4 w-4 animate-spin" : "h-4 w-4"
                    }
                  />
                  Refresh
                </Button>
                <Button variant="ghost" onClick={onLogout}>
                  <LogOut className="h-4 w-4" />
                  Sign Out
                </Button>
              </div>
            </div>
          </div>

          {role === "admin" ? (
            <div className="mt-6 grid grid-cols-1 gap-3 sm:grid-cols-3">
              <div className="rounded-lg border border-[var(--border-1)] bg-[var(--surface-2)] p-4">
                <p className="text-xs uppercase tracking-wide text-[var(--text-2)]">
                  Accounts
                </p>
                <p className="mt-1 text-2xl font-bold text-[var(--text-0)]">
                  {accounts.length}
                </p>
              </div>
              <div className="rounded-lg border border-[var(--border-1)] bg-[var(--surface-2)] p-4">
                <p className="text-xs uppercase tracking-wide text-[var(--text-2)]">
                  Payments
                </p>
                <p className="mt-1 text-2xl font-bold text-[var(--text-0)]">
                  {payments.length}
                </p>
              </div>
              <div className="rounded-lg border border-[var(--border-1)] bg-[var(--surface-2)] p-4">
                <p className="text-xs uppercase tracking-wide text-[var(--text-2)]">
                  Total Balance
                </p>
                <p className="mt-1 text-2xl font-bold text-[var(--text-0)]">
                  ${totalBalance.toFixed(2)}
                </p>
              </div>
            </div>
          ) : (
            <div className="mt-6 grid grid-cols-1 gap-3 sm:grid-cols-3">
              <div className="rounded-lg border border-[var(--border-1)] bg-[var(--surface-2)] p-4">
                <p className="text-xs uppercase tracking-wide text-[var(--text-2)]">
                  Signed In As
                </p>
                <p className="mt-1 text-xl font-bold text-[var(--text-0)]">
                  {session.display_name}
                </p>
              </div>
              <div className="rounded-lg border border-[var(--border-1)] bg-[var(--surface-2)] p-4">
                <p className="text-xs uppercase tracking-wide text-[var(--text-2)]">
                  Current Balance
                </p>
                <p className="mt-1 text-2xl font-bold text-[var(--text-0)]">
                  ${Number(activeUserAccount?.balance ?? 0).toFixed(2)}
                </p>
              </div>
              <div className="rounded-lg border border-[var(--border-1)] bg-[var(--surface-2)] p-4">
                <p className="text-xs uppercase tracking-wide text-[var(--text-2)]">
                  My Payments
                </p>
                <p className="mt-1 text-2xl font-bold text-[var(--text-0)]">
                  {userPayments.length}
                </p>
              </div>
            </div>
          )}
        </header>

        {notice && (
          <div
            className={
              "rounded-lg border px-4 py-3 text-sm " +
              (notice.kind === "success"
                ? "border-emerald-300 bg-emerald-50 text-emerald-800"
                : notice.kind === "error"
                  ? "border-rose-300 bg-rose-50 text-rose-800"
                  : "border-sky-300 bg-sky-50 text-sky-800")
            }
          >
            {notice.text}
          </div>
        )}

        {role === "admin" ? (
          <section className="grid grid-cols-1 gap-5 lg:grid-cols-2">
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <Landmark className="h-5 w-5" /> Accounts
                </CardTitle>
                <CardDescription>
                  Create account records and perform debit or credit operations.
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
                  <Input
                    placeholder="Name"
                    value={accountName}
                    onChange={(event) => setAccountName(event.target.value)}
                  />
                  <Input
                    placeholder="Email"
                    value={accountEmail}
                    onChange={(event) => setAccountEmail(event.target.value)}
                  />
                  <Button onClick={() => void handleCreateAccount()}>
                    Create Account
                  </Button>
                </div>

                <div className="grid grid-cols-1 gap-2 sm:grid-cols-4">
                  <Input
                    placeholder="Account ID"
                    value={balanceAccountId}
                    onChange={(event) =>
                      setBalanceAccountId(event.target.value)
                    }
                  />
                  <Input
                    placeholder="Amount"
                    type="number"
                    value={balanceAmount}
                    onChange={(event) => setBalanceAmount(event.target.value)}
                  />
                  <Button
                    variant="secondary"
                    onClick={() => void handleBalanceUpdate("credit")}
                  >
                    Credit
                  </Button>
                  <Button
                    variant="danger"
                    onClick={() => void handleBalanceUpdate("debit")}
                  >
                    Debit
                  </Button>
                </div>

                <div className="max-h-72 overflow-auto rounded-lg border border-[var(--border-1)]">
                  <table className="w-full text-left text-sm">
                    <thead className="bg-[var(--surface-2)] text-[var(--text-2)]">
                      <tr>
                        <th className="px-3 py-2">ID</th>
                        <th className="px-3 py-2">Name</th>
                        <th className="px-3 py-2">Email</th>
                        <th className="px-3 py-2">Balance</th>
                      </tr>
                    </thead>
                    <tbody>
                      {accounts.map((account) => (
                        <tr
                          key={account.id}
                          className="border-t border-[var(--border-1)]"
                        >
                          <td className="px-3 py-2">{account.id}</td>
                          <td className="px-3 py-2">{account.name}</td>
                          <td className="px-3 py-2">{account.email}</td>
                          <td className="px-3 py-2 font-semibold">
                            ${Number(account.balance).toFixed(2)}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <ArrowLeftRight className="h-5 w-5" /> Payments
                </CardTitle>
                <CardDescription>
                  Execute orchestrated P2P transfers through the FastAPI
                  orchestration layer.
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="grid grid-cols-1 gap-2 sm:grid-cols-4">
                  <Input
                    placeholder="Payer ID"
                    value={payerId}
                    onChange={(event) => setPayerId(event.target.value)}
                  />
                  <Input
                    placeholder="Recipient ID"
                    value={recipientId}
                    onChange={(event) => setRecipientId(event.target.value)}
                  />
                  <Input
                    placeholder="Amount"
                    type="number"
                    value={paymentAmount}
                    onChange={(event) => setPaymentAmount(event.target.value)}
                  />
                  <Button onClick={() => void handleCreatePayment()}>
                    Run Payment
                  </Button>
                </div>

                <div className="space-y-2">
                  {payments
                    .slice()
                    .reverse()
                    .map((payment) => (
                      <div
                        key={payment.id}
                        className="rounded-lg border border-[var(--border-1)] bg-[var(--surface-2)] p-3"
                      >
                        <div className="flex flex-wrap items-center justify-between gap-2">
                          <p className="font-semibold text-[var(--text-0)]">
                            Payment #{payment.id} | $
                            {Number(payment.amount).toFixed(2)}
                          </p>
                          <Badge variant={paymentStatusVariant(payment.status)}>
                            {payment.status}
                          </Badge>
                        </div>
                        <p className="mt-1 text-xs text-[var(--text-2)]">
                          Sender {payment.account_id}
                          {payment.recipient_account_id
                            ? ` -> Recipient ${payment.recipient_account_id}`
                            : ""}
                          {payment.execution_id
                            ? ` | Exec ${payment.execution_id}`
                            : ""}
                        </p>
                      </div>
                    ))}
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <BookOpenText className="h-5 w-5" /> Ledger
                </CardTitle>
                <CardDescription>
                  Review or append ledger entries used for local audit
                  traceability.
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
                  <Input
                    placeholder="Description"
                    value={ledgerDescription}
                    onChange={(event) =>
                      setLedgerDescription(event.target.value)
                    }
                  />
                  <Input
                    placeholder="Amount"
                    type="number"
                    value={ledgerAmount}
                    onChange={(event) => setLedgerAmount(event.target.value)}
                  />
                  <Button
                    variant="secondary"
                    onClick={() => void handleCreateLedgerEntry()}
                  >
                    Add Ledger Entry
                  </Button>
                </div>

                <div className="space-y-2">
                  {ledgerEntries
                    .slice()
                    .reverse()
                    .map((entry) => (
                      <div
                        key={entry.id}
                        className="rounded-lg border border-[var(--border-1)] bg-[var(--surface-2)] p-3"
                      >
                        <p className="font-semibold text-[var(--text-0)]">
                          {entry.description}
                        </p>
                        <p className="text-xs text-[var(--text-2)]">
                          Entry #{entry.id} | Amount $
                          {Number(entry.amount).toFixed(2)}
                        </p>
                      </div>
                    ))}
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <FileText className="h-5 w-5" /> Statements
                </CardTitle>
                <CardDescription>
                  Create and inspect statements by account and period.
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
                  <Input
                    placeholder="Account ID"
                    value={statementAccountId}
                    onChange={(event) =>
                      setStatementAccountId(event.target.value)
                    }
                  />
                  <Input
                    placeholder="Period (YYYY-MM)"
                    value={statementPeriod}
                    onChange={(event) => setStatementPeriod(event.target.value)}
                  />
                  <Button
                    variant="secondary"
                    onClick={() => void handleCreateStatement()}
                  >
                    Generate Statement
                  </Button>
                </div>

                <div className="space-y-2">
                  {statements
                    .slice()
                    .reverse()
                    .map((statement) => (
                      <div
                        key={statement.id}
                        className="rounded-lg border border-[var(--border-1)] bg-[var(--surface-2)] p-3"
                      >
                        <p className="font-semibold text-[var(--text-0)]">
                          Statement #{statement.id}
                        </p>
                        <p className="text-xs text-[var(--text-2)]">
                          Account {statement.account_id} | Period{" "}
                          {statement.period}
                        </p>
                      </div>
                    ))}
                </div>
              </CardContent>
            </Card>
          </section>
        ) : (
          <section className="grid grid-cols-1 gap-5 lg:grid-cols-2">
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <Wallet className="h-5 w-5" /> My Account
                </CardTitle>
                <CardDescription>
                  This profile is bound to your authenticated account.
                </CardDescription>
              </CardHeader>
              <CardContent>
                {activeUserAccount ? (
                  <div className="rounded-lg border border-[var(--border-1)] bg-[var(--surface-2)] p-4">
                    <p className="font-semibold text-[var(--text-0)]">
                      {activeUserAccount.name}
                    </p>
                    <p className="mt-1 text-sm text-[var(--text-2)]">
                      {activeUserAccount.email}
                    </p>
                    <p className="mt-2 text-lg font-bold text-[var(--text-0)]">
                      Balance: ${Number(activeUserAccount.balance).toFixed(2)}
                    </p>
                    <p className="mt-2 text-xs text-[var(--text-2)]">
                      Account ID: {activeUserAccount.id}
                    </p>
                  </div>
                ) : (
                  <div className="rounded-lg border border-dashed border-[var(--border-1)] bg-[var(--surface-2)] p-4 text-sm text-[var(--text-2)]">
                    Account details are loading or unavailable.
                  </div>
                )}
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <ArrowLeftRight className="h-5 w-5" /> Send Money
                </CardTitle>
                <CardDescription>
                  Submit peer-to-peer transfers from your authenticated account.
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
                  <Input
                    placeholder="Recipient ID"
                    value={userRecipientId}
                    onChange={(event) => setUserRecipientId(event.target.value)}
                  />
                  <Input
                    placeholder="Amount"
                    type="number"
                    value={userPaymentAmount}
                    onChange={(event) =>
                      setUserPaymentAmount(event.target.value)
                    }
                  />
                  <Button
                    onClick={() => void handleUserPayment()}
                    disabled={!activeUserAccount}
                  >
                    Send Payment
                  </Button>
                </div>
                <p className="text-xs text-[var(--text-2)]">
                  Sender account is fixed by your session and cannot be
                  overridden.
                </p>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <Wallet className="h-5 w-5" /> Top Up Balance
                </CardTitle>
                <CardDescription>
                  Add funds to your own account only.
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                  <Input
                    placeholder="Amount"
                    type="number"
                    value={userTopUpAmount}
                    onChange={(event) => setUserTopUpAmount(event.target.value)}
                  />
                  <Button
                    variant="secondary"
                    onClick={() => void handleUserTopUp()}
                    disabled={!activeUserAccount}
                  >
                    Top Up
                  </Button>
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <FileText className="h-5 w-5" /> My Statements
                </CardTitle>
                <CardDescription>
                  Generate and review statements for your own account.
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
                  <Input
                    placeholder="Period (YYYY-MM)"
                    value={userStatementPeriod}
                    onChange={(event) =>
                      setUserStatementPeriod(event.target.value)
                    }
                  />
                  <Button
                    variant="secondary"
                    onClick={() => void handleUserStatement()}
                    disabled={!activeUserAccount}
                  >
                    Generate
                  </Button>
                </div>

                <div className="space-y-2">
                  {userStatements.length === 0 ? (
                    <div className="rounded-lg border border-dashed border-[var(--border-1)] bg-[var(--surface-2)] p-4 text-sm text-[var(--text-2)]">
                      No statements yet for this account.
                    </div>
                  ) : (
                    userStatements
                      .slice()
                      .reverse()
                      .map((statement) => (
                        <div
                          key={statement.id}
                          className="rounded-lg border border-[var(--border-1)] bg-[var(--surface-2)] p-3"
                        >
                          <p className="font-semibold text-[var(--text-0)]">
                            Statement #{statement.id}
                          </p>
                          <p className="text-xs text-[var(--text-2)]">
                            Period {statement.period}
                          </p>
                        </div>
                      ))
                  )}
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <ArrowLeftRight className="h-5 w-5" /> My Payments
                </CardTitle>
                <CardDescription>
                  Review transfers sent and received by your account.
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-2">
                {userPayments.length === 0 ? (
                  <div className="rounded-lg border border-dashed border-[var(--border-1)] bg-[var(--surface-2)] p-4 text-sm text-[var(--text-2)]">
                    No payment activity yet.
                  </div>
                ) : (
                  userPayments
                    .slice()
                    .reverse()
                    .map((payment) => {
                      const isOutgoing =
                        payment.account_id === selectedUserAccountId;
                      return (
                        <div
                          key={payment.id}
                          className="rounded-lg border border-[var(--border-1)] bg-[var(--surface-2)] p-3"
                        >
                          <div className="flex flex-wrap items-center justify-between gap-2">
                            <p className="font-semibold text-[var(--text-0)]">
                              {isOutgoing ? "Sent" : "Received"} $
                              {Number(payment.amount).toFixed(2)}
                            </p>
                            <Badge
                              variant={paymentStatusVariant(payment.status)}
                            >
                              {payment.status}
                            </Badge>
                          </div>
                          <p className="mt-1 text-xs text-[var(--text-2)]">
                            {isOutgoing
                              ? `To account ${payment.recipient_account_id ?? "Unknown"}`
                              : `From account ${payment.account_id}`}
                            {payment.execution_id
                              ? ` | Exec ${payment.execution_id}`
                              : ""}
                          </p>
                        </div>
                      );
                    })
                )}
              </CardContent>
            </Card>
          </section>
        )}
      </section>
    </main>
  );
}

function App() {
  const navigate = useNavigate();
  const [session, setSession] = useState<AuthSession | null>(() =>
    loadStoredSession(),
  );
  const [isSessionReady, setIsSessionReady] = useState(false);

  useEffect(() => {
    setAuthToken(session?.access_token ?? null);
    persistSession(session);
  }, [session]);

  useEffect(() => {
    let isCancelled = false;

    async function validateSession() {
      if (!session) {
        setIsSessionReady(true);
        return;
      }

      setIsSessionReady(false);
      try {
        setAuthToken(session.access_token);
        const profile = await getAuthMe();

        const accountMatches =
          (profile.account_id ?? null) === (session.account_id ?? null);
        const roleMatches = profile.role === session.role;

        if (!roleMatches || !accountMatches) {
          throw new Error("Session authorization mismatch");
        }

        if (!isCancelled) {
          setIsSessionReady(true);
        }
      } catch {
        if (!isCancelled) {
          setSession(null);
          setAuthToken(null);
          setIsSessionReady(true);
        }
      }
    }

    void validateSession();

    return () => {
      isCancelled = true;
    };
  }, [session]);

  function handleLogout() {
    setSession(null);
    setAuthToken(null);
    navigate("/login", { replace: true });
  }

  if (!isSessionReady) {
    return (
      <main className="min-h-screen px-4 py-10 sm:px-8">
        <section className="mx-auto max-w-2xl rounded-2xl border border-[var(--border-1)] bg-[var(--surface-1)] p-8 text-center">
          <p className="text-sm font-semibold uppercase tracking-wide text-[var(--text-2)]">
            Validating Session
          </p>
          <p className="mt-2 text-lg font-bold text-[var(--text-0)]">
            Please wait...
          </p>
        </section>
      </main>
    );
  }

  const defaultRoute = session ? roleHome(session.role) : "/login";

  return (
    <Routes>
      <Route
        path="/login"
        element={<LoginPage session={session} onLogin={setSession} />}
      />
      <Route
        path="/admin"
        element={
          <RoleRouteGuard session={session} requiredRole="admin">
            {session ? (
              <Workspace session={session} onLogout={handleLogout} />
            ) : null}
          </RoleRouteGuard>
        }
      />
      <Route
        path="/app"
        element={
          <RoleRouteGuard session={session} requiredRole="user">
            {session ? (
              <Workspace session={session} onLogout={handleLogout} />
            ) : null}
          </RoleRouteGuard>
        }
      />
      <Route path="*" element={<Navigate to={defaultRoute} replace />} />
    </Routes>
  );
}

export default App;
