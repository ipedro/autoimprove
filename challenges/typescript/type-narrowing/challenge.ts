// TypeScript Challenge: Type Narrowing
// Fix the incorrect type narrowing patterns in this API response handler.

type SuccessResponse<T> = {
  status: "success";
  data: T;
  metadata?: { cached: boolean; ttl: number };
};

type ErrorResponse = {
  status: "error";
  error: string;
  retryable: boolean;
};

type PendingResponse = {
  status: "pending";
  jobId: string;
};

type ApiResponse<T> = SuccessResponse<T> | ErrorResponse | PendingResponse;

interface User {
  id: number;
  name: string;
  email: string;
}

// BUG: incorrect narrowing — checks !response.error instead of response.status === "success".
// PendingResponse also has no .error field, so this returns true for pending responses,
// causing response.data access on a PendingResponse which has no .data property.
function extractData<T>(response: ApiResponse<T>): T | null {
  if (!("error" in response)) {
    // Both SuccessResponse and PendingResponse pass this check
    return (response as SuccessResponse<T>).data; // BUG: may be undefined for PendingResponse
  }
  return null;
}

// BUG: accesses response.metadata.cached without null-checking optional metadata field.
function isCachedResponse<T>(response: ApiResponse<T>): boolean {
  if (response.status === "success") {
    return response.metadata.cached; // BUG: metadata is optional, may be undefined
  }
  return false;
}

// CORRECT: uses discriminated union narrowing via status field.
function isRetryable<T>(response: ApiResponse<T>): boolean {
  if (response.status === "error") {
    return response.retryable;
  }
  return false;
}

// CORRECT: proper exhaustive narrowing using the status discriminant.
function describeResponse<T>(response: ApiResponse<T>): string {
  switch (response.status) {
    case "success":
      return `Success: ${JSON.stringify(response.data)}`;
    case "error":
      return `Error: ${response.error} (retryable: ${response.retryable})`;
    case "pending":
      return `Pending job: ${response.jobId}`;
  }
}

// CORRECT: safe metadata access with optional chaining.
function getCacheTtl<T>(response: ApiResponse<T>): number | undefined {
  if (response.status === "success") {
    return response.metadata?.ttl;
  }
  return undefined;
}
