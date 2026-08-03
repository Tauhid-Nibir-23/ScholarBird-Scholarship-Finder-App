"""In-memory provider diagnostics and health classification."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone


@dataclass(frozen=True)
class ProviderHealth:
    status: str
    reasons: tuple[str, ...] = ()


@dataclass
class ProviderDiagnostics:
    records_scraped: int = 0
    records_valid: int = 0
    records_rejected: int = 0
    records_uploaded: int = 0
    duplicates_found: int = 0
    total_processing_time: float = 0.0
    processed_batches: int = 0
    last_success: str | None = None
    last_failure: str | None = None

    @property
    def average_processing_time(self) -> float:
        return self.total_processing_time / self.processed_batches if self.processed_batches else 0.0

    def record_batch(self, *, scraped: int, valid: int, rejected: int, uploaded: int, duplicates: int, processing_time: float, success: bool = True) -> None:
        self.records_scraped += scraped; self.records_valid += valid; self.records_rejected += rejected; self.records_uploaded += uploaded; self.duplicates_found += duplicates; self.total_processing_time += processing_time; self.processed_batches += 1
        now = datetime.now(timezone.utc).isoformat()
        if success: self.last_success = now
        else: self.last_failure = now

    def health(self) -> ProviderHealth:
        if self.last_failure and not self.last_success: return ProviderHealth("failed", ("No successful provider run",))
        if self.records_scraped and not self.records_valid: return ProviderHealth("warning", ("No valid records produced",))
        if self.records_rejected > self.records_valid: return ProviderHealth("warning", ("Rejections exceed valid records",))
        return ProviderHealth("healthy")
