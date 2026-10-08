CREATE TABLE "app_releases" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"version_name" text NOT NULL,
	"version_code" integer NOT NULL,
	"release_notes" text DEFAULT '' NOT NULL,
	"force_update" boolean DEFAULT false NOT NULL,
	"sha256" text NOT NULL,
	"size_bytes" integer NOT NULL,
	"stored_name" text NOT NULL,
	"is_current" boolean DEFAULT false NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "app_releases_version_code_unique" UNIQUE("version_code")
);
--> statement-breakpoint
CREATE TABLE "content_documents" (
	"release_id" uuid NOT NULL,
	"kind" text NOT NULL,
	"body" jsonb NOT NULL,
	CONSTRAINT "content_documents_release_id_kind_pk" PRIMARY KEY("release_id","kind")
);
--> statement-breakpoint
ALTER TABLE "content_documents" ADD CONSTRAINT "content_documents_release_id_content_releases_id_fk" FOREIGN KEY ("release_id") REFERENCES "public"."content_releases"("id") ON DELETE no action ON UPDATE no action;