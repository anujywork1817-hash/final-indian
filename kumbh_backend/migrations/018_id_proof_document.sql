-- ============================================
-- 018_id_proof_document.sql
-- Lets a guest upload their Aadhaar (or other ID proof) as an
-- image/PDF alongside the existing free-text id_proof number, and
-- lets an admin view/download it against the booking in the admin
-- panel. Stored privately in S3 (never publicly readable, unlike the
-- tent-images bucket) — this column holds the S3 object key, not a
-- public URL; admins reach the file via a short-lived presigned URL
-- generated on request (booking-service/documents.go).
-- ============================================

ALTER TABLE bookings ADD COLUMN IF NOT EXISTS id_proof_doc_key VARCHAR(300);
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS id_proof_doc_uploaded_at TIMESTAMPTZ;
