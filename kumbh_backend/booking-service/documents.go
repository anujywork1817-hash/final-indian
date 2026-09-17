package main

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/gin-gonic/gin"
)

// Lets a guest attach a photo/scan of their Aadhaar (or other ID
// proof) to a booking — alongside the existing free-text id_proof
// number field — and lets an admin view it against that booking.
//
// Stored privately in its own bucket (never public-read, unlike the
// tent-images bucket): only the S3 object key is kept in the
// bookings row (migration 018), and admins reach the file through a
// short-lived presigned GET URL minted on request, not a public URL.
//
// Credentials come from the EC2 instance role (aws-elasticbeanstalk-
// ec2-role) via the SDK's default credential chain — no access keys
// in the environment, matching how this app has no other AWS
// credentials configured anywhere else. That role has a scoped
// inline policy (KumbhDocsBucketAccess) granting only
// s3:PutObject/s3:GetObject on this one bucket.

const (
	maxIDProofDocBytes = 8 << 20 // 8 MB — a phone photo or scanned PDF comfortably fits

	docsBucketEnv = "ID_PROOF_DOCS_BUCKET"
	docsRegionEnv = "AWS_REGION"
)

var (
	s3Client   *s3.Client
	docsBucket string
)

func initDocumentsStore() {
	docsBucket = os.Getenv(docsBucketEnv)
	if docsBucket == "" {
		// Not fatal — the two endpoints below fail cleanly per-request
		// if this is unset, rather than crashing every other feature
		// in the service at startup.
		log.Printf("⚠️  %s not set — Aadhaar document upload/download is disabled", docsBucketEnv)
		return
	}
	region := os.Getenv(docsRegionEnv)
	if region == "" {
		region = "ap-south-1"
	}
	cfg, err := awsconfig.LoadDefaultConfig(context.Background(), awsconfig.WithRegion(region))
	if err != nil {
		log.Printf("⚠️  could not load AWS config for document storage: %v", err)
		return
	}
	s3Client = s3.NewFromConfig(cfg)
}

var allowedIDProofDocTypes = map[string]string{
	"image/jpeg":      ".jpg",
	"image/png":       ".png",
	"application/pdf": ".pdf",
}

// POST /bookings/:ref/id-proof-doc — multipart upload, called by the
// guest right after createBooking succeeds (or any time after, while
// the booking is still theirs). Not part of createBooking itself
// since that binds pure JSON; this stays a small, separate step so a
// failed/skipped upload never blocks the booking or payment flow.
func uploadIDProofDoc(c *gin.Context) {
	if s3Client == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "document upload is not available"})
		return
	}
	phone := verifiedPhone(c)
	if phone == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	ref := c.Param("ref")

	var owner string
	if err := db.QueryRow(`SELECT phone FROM bookings WHERE booking_ref = $1`, ref).Scan(&owner); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "booking not found"})
		return
	}
	if owner != phone {
		c.JSON(http.StatusForbidden, gin.H{"error": "not your booking"})
		return
	}

	file, header, err := c.Request.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "no file uploaded"})
		return
	}
	defer file.Close()

	if header.Size > maxIDProofDocBytes {
		c.JSON(http.StatusRequestEntityTooLarge, gin.H{"error": "file too large — max 8 MB"})
		return
	}

	// Sniff the real content type from the file bytes rather than
	// trusting the client-supplied Content-Type header, which is
	// trivial to spoof.
	head := make([]byte, 512)
	n, _ := io.ReadFull(file, head)
	contentType := http.DetectContentType(head[:n])
	ext, ok := allowedIDProofDocTypes[contentType]
	if !ok {
		c.JSON(http.StatusUnsupportedMediaType, gin.H{"error": "only JPEG, PNG or PDF files are accepted"})
		return
	}
	body := io.MultiReader(strings.NewReader(string(head[:n])), file)

	key := fmt.Sprintf("id-proof/%s/%s%s", ref, randomHex(16), ext)

	_, err = s3Client.PutObject(c.Request.Context(), &s3.PutObjectInput{
		Bucket:      aws.String(docsBucket),
		Key:         aws.String(key),
		Body:        body,
		ContentType: aws.String(contentType),
		// Private by default (no ACL set) — the bucket also has all
		// four public-access-block settings on, so a stray public ACL
		// couldn't leak this even if one were set by mistake.
	})
	if err != nil {
		log.Printf("id-proof-doc upload failed for %s: %v", ref, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "upload failed, please try again"})
		return
	}

	if _, err := db.Exec(`
		UPDATE bookings
		SET id_proof_doc_key = $1, id_proof_doc_uploaded_at = NOW()
		WHERE booking_ref = $2
	`, key, ref); err != nil {
		log.Printf("id-proof-doc DB update failed for %s: %v", ref, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "upload saved but could not be linked — please retry"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "ID proof document uploaded"})
}

// GET /admin/bookings/:ref/id-proof-doc — returns a presigned URL
// (valid 15 minutes) the admin panel opens directly in a new tab /
// <img>/<iframe> src, rather than proxying the file's bytes through
// this service.
func adminGetIDProofDocURL(c *gin.Context) {
	if s3Client == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "document storage is not available"})
		return
	}
	ref := c.Param("ref")

	var key sql.NullString
	err := db.QueryRow(`SELECT id_proof_doc_key FROM bookings WHERE booking_ref = $1`, ref).Scan(&key)
	if err != nil || !key.Valid || key.String == "" {
		c.JSON(http.StatusNotFound, gin.H{"error": "no ID proof document uploaded for this booking"})
		return
	}

	presignClient := s3.NewPresignClient(s3Client)
	presigned, err := presignClient.PresignGetObject(c.Request.Context(), &s3.GetObjectInput{
		Bucket: aws.String(docsBucket),
		Key:    aws.String(key.String),
	}, s3.WithPresignExpires(15*time.Minute))
	if err != nil {
		log.Printf("id-proof-doc presign failed for %s: %v", ref, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not generate document link"})
		return
	}

	admin, _ := adminRoleFromToken(c)
	logAdminAction(admin, "view_id_proof_doc", "booking", ref, "")

	c.JSON(http.StatusOK, gin.H{"url": presigned.URL, "expires_in_seconds": 900})
}

func randomHex(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		// crypto/rand failing is effectively unrecoverable; fall back
		// to a timestamp so the request doesn't just panic.
		return fmt.Sprintf("%d", time.Now().UnixNano())
	}
	return hex.EncodeToString(b)
}
