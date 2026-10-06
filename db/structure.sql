SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: files_node_kind; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.files_node_kind AS ENUM (
    'folder',
    'file'
);


--
-- Name: files_nodes_cascade_ancestor_ids(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.files_nodes_cascade_ancestor_ids() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE files_nodes SET ancestor_ids = '{}' WHERE parent_id = NEW.id;
  RETURN NULL;
END;
$$;


--
-- Name: files_nodes_set_ancestor_ids(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.files_nodes_set_ancestor_ids() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.parent_id IS NULL THEN
    NEW.ancestor_ids := '{}';
  ELSE
    SELECT ancestor_ids || id INTO NEW.ancestor_ids FROM files_nodes WHERE id = NEW.parent_id;
    IF NEW.id = ANY(NEW.ancestor_ids) THEN
      RAISE EXCEPTION 'files_nodes % cannot be moved under itself', NEW.id
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: files_activities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.files_activities (
    id bigint NOT NULL,
    tenant_id uuid NOT NULL,
    node_id bigint,
    actor_id bigint,
    action character varying NOT NULL,
    detail jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT files_activities_action_check CHECK (((action)::text = ANY ((ARRAY['created'::character varying, 'updated'::character varying, 'renamed'::character varying, 'moved'::character varying, 'deleted'::character varying, 'restored'::character varying, 'purged'::character varying, 'shared'::character varying])::text[])))
);


--
-- Name: files_activities_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.files_activities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: files_activities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.files_activities_id_seq OWNED BY public.files_activities.id;


--
-- Name: files_drives; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.files_drives (
    id bigint NOT NULL,
    tenant_id uuid NOT NULL,
    kind character varying NOT NULL,
    owner_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT files_drives_kind_check CHECK (((((kind)::text = 'shared'::text) AND (owner_id IS NULL)) OR (((kind)::text = 'personal'::text) AND (owner_id IS NOT NULL))))
);


--
-- Name: files_drives_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.files_drives_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: files_drives_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.files_drives_id_seq OWNED BY public.files_drives.id;


--
-- Name: files_nodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.files_nodes (
    id bigint NOT NULL,
    tenant_id uuid NOT NULL,
    drive_id bigint NOT NULL,
    parent_id bigint,
    kind public.files_node_kind NOT NULL,
    name character varying NOT NULL,
    creator_id bigint,
    current_version_id bigint,
    byte_size bigint DEFAULT 0 NOT NULL,
    deleted_at timestamp(6) without time zone,
    deleted_root_id bigint,
    deleted_by_id bigint,
    purge_after timestamp(6) without time zone,
    purged_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    ancestor_ids bigint[] DEFAULT '{}'::bigint[] NOT NULL,
    CONSTRAINT files_nodes_folder_size_check CHECK (((kind = 'file'::public.files_node_kind) OR (byte_size = 0))),
    CONSTRAINT files_nodes_folder_version_check CHECK (((kind = 'file'::public.files_node_kind) OR (current_version_id IS NULL)))
);


--
-- Name: files_nodes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.files_nodes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: files_nodes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.files_nodes_id_seq OWNED BY public.files_nodes.id;


--
-- Name: files_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.files_permissions (
    id bigint NOT NULL,
    tenant_id uuid NOT NULL,
    node_id bigint NOT NULL,
    group_id bigint,
    tenant_user_id bigint,
    role character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT files_permissions_role_check CHECK (((role)::text = ANY ((ARRAY['viewer'::character varying, 'editor'::character varying, 'manager'::character varying, 'none'::character varying])::text[]))),
    CONSTRAINT files_permissions_subject_check CHECK (((group_id IS NULL) <> (tenant_user_id IS NULL)))
);


--
-- Name: files_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.files_permissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: files_permissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.files_permissions_id_seq OWNED BY public.files_permissions.id;


--
-- Name: files_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.files_settings (
    id bigint NOT NULL,
    tenant_id uuid NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    storage_limit_bytes bigint DEFAULT '10737418240'::bigint NOT NULL,
    storage_used_bytes bigint DEFAULT 0 NOT NULL,
    version_retention_days integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT files_settings_retention_check CHECK (((version_retention_days IS NULL) OR (version_retention_days > 0))),
    CONSTRAINT files_settings_used_check CHECK ((storage_used_bytes >= 0))
);


--
-- Name: files_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.files_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: files_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.files_settings_id_seq OWNED BY public.files_settings.id;


--
-- Name: files_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.files_versions (
    id bigint NOT NULL,
    tenant_id uuid NOT NULL,
    node_id bigint NOT NULL,
    number integer NOT NULL,
    label character varying,
    byte_size bigint NOT NULL,
    content_type character varying,
    creator_id bigint,
    purged_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: files_versions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.files_versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: files_versions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.files_versions_id_seq OWNED BY public.files_versions.id;


--
-- Name: group_members; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.group_members (
    id bigint NOT NULL,
    tenant_id uuid NOT NULL,
    group_id bigint NOT NULL,
    tenant_user_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: group_members_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.group_members_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: group_members_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.group_members_id_seq OWNED BY public.group_members.id;


--
-- Name: groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.groups (
    id bigint NOT NULL,
    tenant_id uuid NOT NULL,
    parent_id bigint,
    kind character varying DEFAULT 'department'::character varying NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT groups_kind_check CHECK (((kind)::text = ANY ((ARRAY['department'::character varying, 'everyone'::character varying])::text[])))
);


--
-- Name: groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.groups_id_seq OWNED BY public.groups.id;


--
-- Name: operators; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.operators (
    id bigint NOT NULL,
    email public.citext NOT NULL,
    password_digest character varying NOT NULL,
    display_name character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    last_signed_in_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT operators_status_check CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'suspended'::character varying])::text[])))
);


--
-- Name: operators_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.operators_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: operators_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.operators_id_seq OWNED BY public.operators.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: tenant_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenant_users (
    id bigint NOT NULL,
    tenant_id uuid NOT NULL,
    user_id bigint NOT NULL,
    display_name character varying NOT NULL,
    role character varying DEFAULT 'member'::character varying NOT NULL,
    status character varying DEFAULT 'invited'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT tenant_users_role_check CHECK (((role)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'member'::character varying])::text[]))),
    CONSTRAINT tenant_users_status_check CHECK (((status)::text = ANY ((ARRAY['invited'::character varying, 'active'::character varying, 'suspended'::character varying])::text[])))
);


--
-- Name: tenant_users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tenant_users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tenant_users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tenant_users_id_seq OWNED BY public.tenant_users.id;


--
-- Name: tenants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenants (
    id uuid DEFAULT uuidv7() NOT NULL,
    name character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT tenants_status_check CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'suspended'::character varying])::text[])))
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    email public.citext NOT NULL,
    password_digest character varying NOT NULL,
    email_verified_at timestamp(6) without time zone,
    email_verification_token character varying,
    email_verification_token_expires_at timestamp(6) without time zone,
    password_reset_token character varying,
    password_reset_token_expires_at timestamp(6) without time zone,
    last_signed_in_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: files_activities id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_activities ALTER COLUMN id SET DEFAULT nextval('public.files_activities_id_seq'::regclass);


--
-- Name: files_drives id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_drives ALTER COLUMN id SET DEFAULT nextval('public.files_drives_id_seq'::regclass);


--
-- Name: files_nodes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_nodes ALTER COLUMN id SET DEFAULT nextval('public.files_nodes_id_seq'::regclass);


--
-- Name: files_permissions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_permissions ALTER COLUMN id SET DEFAULT nextval('public.files_permissions_id_seq'::regclass);


--
-- Name: files_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_settings ALTER COLUMN id SET DEFAULT nextval('public.files_settings_id_seq'::regclass);


--
-- Name: files_versions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_versions ALTER COLUMN id SET DEFAULT nextval('public.files_versions_id_seq'::regclass);


--
-- Name: group_members id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_members ALTER COLUMN id SET DEFAULT nextval('public.group_members_id_seq'::regclass);


--
-- Name: groups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.groups ALTER COLUMN id SET DEFAULT nextval('public.groups_id_seq'::regclass);


--
-- Name: operators id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operators ALTER COLUMN id SET DEFAULT nextval('public.operators_id_seq'::regclass);


--
-- Name: tenant_users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_users ALTER COLUMN id SET DEFAULT nextval('public.tenant_users_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: files_activities files_activities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_activities
    ADD CONSTRAINT files_activities_pkey PRIMARY KEY (id);


--
-- Name: files_drives files_drives_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_drives
    ADD CONSTRAINT files_drives_pkey PRIMARY KEY (id);


--
-- Name: files_nodes files_nodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_nodes
    ADD CONSTRAINT files_nodes_pkey PRIMARY KEY (id);


--
-- Name: files_permissions files_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_permissions
    ADD CONSTRAINT files_permissions_pkey PRIMARY KEY (id);


--
-- Name: files_settings files_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_settings
    ADD CONSTRAINT files_settings_pkey PRIMARY KEY (id);


--
-- Name: files_versions files_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_versions
    ADD CONSTRAINT files_versions_pkey PRIMARY KEY (id);


--
-- Name: group_members group_members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_members
    ADD CONSTRAINT group_members_pkey PRIMARY KEY (id);


--
-- Name: groups groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.groups
    ADD CONSTRAINT groups_pkey PRIMARY KEY (id);


--
-- Name: operators operators_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operators
    ADD CONSTRAINT operators_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: tenant_users tenant_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_users
    ADD CONSTRAINT tenant_users_pkey PRIMARY KEY (id);


--
-- Name: tenants tenants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenants
    ADD CONSTRAINT tenants_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: index_files_activities_on_node_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_files_activities_on_node_id_and_created_at ON public.files_activities USING btree (node_id, created_at);


--
-- Name: index_files_activities_on_tenant_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_files_activities_on_tenant_id_and_created_at ON public.files_activities USING btree (tenant_id, created_at);


--
-- Name: index_files_drives_on_owner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_files_drives_on_owner_id ON public.files_drives USING btree (owner_id) WHERE ((kind)::text = 'personal'::text);


--
-- Name: index_files_drives_on_shared_per_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_files_drives_on_shared_per_tenant ON public.files_drives USING btree (tenant_id) WHERE ((kind)::text = 'shared'::text);


--
-- Name: index_files_drives_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_files_drives_on_tenant_id ON public.files_drives USING btree (tenant_id);


--
-- Name: index_files_nodes_on_current_version_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_files_nodes_on_current_version_id ON public.files_nodes USING btree (current_version_id);


--
-- Name: index_files_nodes_on_deleted_root_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_files_nodes_on_deleted_root_id ON public.files_nodes USING btree (deleted_root_id);


--
-- Name: index_files_nodes_on_drive_id_and_parent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_files_nodes_on_drive_id_and_parent_id ON public.files_nodes USING btree (drive_id, parent_id);


--
-- Name: index_files_nodes_on_parent_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_files_nodes_on_parent_id_and_name ON public.files_nodes USING btree (parent_id, name) WHERE ((deleted_at IS NULL) AND (parent_id IS NOT NULL));


--
-- Name: index_files_nodes_on_root_per_drive; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_files_nodes_on_root_per_drive ON public.files_nodes USING btree (drive_id) WHERE (parent_id IS NULL);


--
-- Name: index_files_nodes_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_files_nodes_on_tenant_id ON public.files_nodes USING btree (tenant_id);


--
-- Name: index_files_permissions_on_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_files_permissions_on_group_id ON public.files_permissions USING btree (group_id);


--
-- Name: index_files_permissions_on_node_id_and_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_files_permissions_on_node_id_and_group_id ON public.files_permissions USING btree (node_id, group_id) WHERE (group_id IS NOT NULL);


--
-- Name: index_files_permissions_on_node_id_and_tenant_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_files_permissions_on_node_id_and_tenant_user_id ON public.files_permissions USING btree (node_id, tenant_user_id) WHERE (tenant_user_id IS NOT NULL);


--
-- Name: index_files_permissions_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_files_permissions_on_tenant_id ON public.files_permissions USING btree (tenant_id);


--
-- Name: index_files_permissions_on_tenant_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_files_permissions_on_tenant_user_id ON public.files_permissions USING btree (tenant_user_id);


--
-- Name: index_files_settings_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_files_settings_on_tenant_id ON public.files_settings USING btree (tenant_id);


--
-- Name: index_files_versions_on_node_id_and_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_files_versions_on_node_id_and_number ON public.files_versions USING btree (node_id, number);


--
-- Name: index_files_versions_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_files_versions_on_tenant_id ON public.files_versions USING btree (tenant_id);


--
-- Name: index_group_members_on_group_id_and_tenant_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_group_members_on_group_id_and_tenant_user_id ON public.group_members USING btree (group_id, tenant_user_id);


--
-- Name: index_group_members_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_group_members_on_tenant_id ON public.group_members USING btree (tenant_id);


--
-- Name: index_group_members_on_tenant_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_group_members_on_tenant_user_id ON public.group_members USING btree (tenant_user_id);


--
-- Name: index_groups_on_everyone_per_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_groups_on_everyone_per_tenant ON public.groups USING btree (tenant_id) WHERE ((kind)::text = 'everyone'::text);


--
-- Name: index_groups_on_tenant_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_groups_on_tenant_id_and_name ON public.groups USING btree (tenant_id, name) WHERE (parent_id IS NULL);


--
-- Name: index_groups_on_tenant_id_and_parent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_groups_on_tenant_id_and_parent_id ON public.groups USING btree (tenant_id, parent_id);


--
-- Name: index_groups_on_tenant_id_and_parent_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_groups_on_tenant_id_and_parent_id_and_name ON public.groups USING btree (tenant_id, parent_id, name) WHERE (parent_id IS NOT NULL);


--
-- Name: index_operators_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_operators_on_email ON public.operators USING btree (email);


--
-- Name: index_tenant_users_on_tenant_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tenant_users_on_tenant_id_and_user_id ON public.tenant_users USING btree (tenant_id, user_id);


--
-- Name: index_tenant_users_on_user_id_and_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tenant_users_on_user_id_and_tenant_id ON public.tenant_users USING btree (user_id, tenant_id);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_email_verification_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email_verification_token ON public.users USING btree (email_verification_token) WHERE (email_verification_token IS NOT NULL);


--
-- Name: index_users_on_password_reset_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_password_reset_token ON public.users USING btree (password_reset_token) WHERE (password_reset_token IS NOT NULL);


--
-- Name: files_nodes files_nodes_cascade_ancestor_ids; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER files_nodes_cascade_ancestor_ids AFTER UPDATE OF parent_id, ancestor_ids ON public.files_nodes FOR EACH ROW WHEN ((old.ancestor_ids IS DISTINCT FROM new.ancestor_ids)) EXECUTE FUNCTION public.files_nodes_cascade_ancestor_ids();


--
-- Name: files_nodes files_nodes_set_ancestor_ids; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER files_nodes_set_ancestor_ids BEFORE INSERT OR UPDATE OF parent_id, ancestor_ids ON public.files_nodes FOR EACH ROW EXECUTE FUNCTION public.files_nodes_set_ancestor_ids();


--
-- Name: files_nodes fk_rails_036eed7978; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_nodes
    ADD CONSTRAINT fk_rails_036eed7978 FOREIGN KEY (current_version_id) REFERENCES public.files_versions(id) ON DELETE SET NULL;


--
-- Name: groups fk_rails_13822f50e5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.groups
    ADD CONSTRAINT fk_rails_13822f50e5 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: files_nodes fk_rails_21a3ca0c04; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_nodes
    ADD CONSTRAINT fk_rails_21a3ca0c04 FOREIGN KEY (creator_id) REFERENCES public.tenant_users(id) ON DELETE SET NULL;


--
-- Name: files_nodes fk_rails_275e61ed0b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_nodes
    ADD CONSTRAINT fk_rails_275e61ed0b FOREIGN KEY (parent_id) REFERENCES public.files_nodes(id) ON DELETE CASCADE;


--
-- Name: files_drives fk_rails_2b1e25a6ad; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_drives
    ADD CONSTRAINT fk_rails_2b1e25a6ad FOREIGN KEY (owner_id) REFERENCES public.tenant_users(id) ON DELETE CASCADE;


--
-- Name: files_activities fk_rails_3037e5d5e9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_activities
    ADD CONSTRAINT fk_rails_3037e5d5e9 FOREIGN KEY (node_id) REFERENCES public.files_nodes(id) ON DELETE SET NULL;


--
-- Name: files_permissions fk_rails_32e6c168ad; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_permissions
    ADD CONSTRAINT fk_rails_32e6c168ad FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: files_nodes fk_rails_396179183d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_nodes
    ADD CONSTRAINT fk_rails_396179183d FOREIGN KEY (drive_id) REFERENCES public.files_drives(id) ON DELETE CASCADE;


--
-- Name: files_nodes fk_rails_5307dfb34f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_nodes
    ADD CONSTRAINT fk_rails_5307dfb34f FOREIGN KEY (deleted_root_id) REFERENCES public.files_nodes(id) ON DELETE CASCADE;


--
-- Name: files_activities fk_rails_5e3aef7a16; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_activities
    ADD CONSTRAINT fk_rails_5e3aef7a16 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: files_settings fk_rails_782386ed63; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_settings
    ADD CONSTRAINT fk_rails_782386ed63 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: group_members fk_rails_7a0abeaa65; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_members
    ADD CONSTRAINT fk_rails_7a0abeaa65 FOREIGN KEY (tenant_user_id) REFERENCES public.tenant_users(id) ON DELETE CASCADE;


--
-- Name: files_permissions fk_rails_7bbecc3711; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_permissions
    ADD CONSTRAINT fk_rails_7bbecc3711 FOREIGN KEY (node_id) REFERENCES public.files_nodes(id) ON DELETE CASCADE;


--
-- Name: files_activities fk_rails_7dd9f8a06b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_activities
    ADD CONSTRAINT fk_rails_7dd9f8a06b FOREIGN KEY (actor_id) REFERENCES public.tenant_users(id) ON DELETE SET NULL;


--
-- Name: files_versions fk_rails_b7337e7741; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_versions
    ADD CONSTRAINT fk_rails_b7337e7741 FOREIGN KEY (creator_id) REFERENCES public.tenant_users(id) ON DELETE SET NULL;


--
-- Name: files_nodes fk_rails_bccaddf537; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_nodes
    ADD CONSTRAINT fk_rails_bccaddf537 FOREIGN KEY (deleted_by_id) REFERENCES public.tenant_users(id) ON DELETE SET NULL;


--
-- Name: groups fk_rails_be49f097d1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.groups
    ADD CONSTRAINT fk_rails_be49f097d1 FOREIGN KEY (parent_id) REFERENCES public.groups(id) ON DELETE CASCADE;


--
-- Name: files_drives fk_rails_ccbb849065; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_drives
    ADD CONSTRAINT fk_rails_ccbb849065 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: files_versions fk_rails_d6a08f0ebf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_versions
    ADD CONSTRAINT fk_rails_d6a08f0ebf FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: tenant_users fk_rails_e15916f8bf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_users
    ADD CONSTRAINT fk_rails_e15916f8bf FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: tenant_users fk_rails_e3b237e564; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_users
    ADD CONSTRAINT fk_rails_e3b237e564 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: files_permissions fk_rails_e637e287a4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_permissions
    ADD CONSTRAINT fk_rails_e637e287a4 FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE;


--
-- Name: group_members fk_rails_e9fdb70ec5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_members
    ADD CONSTRAINT fk_rails_e9fdb70ec5 FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE;


--
-- Name: files_versions fk_rails_f262e14a74; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_versions
    ADD CONSTRAINT fk_rails_f262e14a74 FOREIGN KEY (node_id) REFERENCES public.files_nodes(id) ON DELETE CASCADE;


--
-- Name: group_members fk_rails_f45936ea8a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_members
    ADD CONSTRAINT fk_rails_f45936ea8a FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: files_nodes fk_rails_f66ac37be2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_nodes
    ADD CONSTRAINT fk_rails_f66ac37be2 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;


--
-- Name: files_permissions fk_rails_f8fa1ce4b3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.files_permissions
    ADD CONSTRAINT fk_rails_f8fa1ce4b3 FOREIGN KEY (tenant_user_id) REFERENCES public.tenant_users(id) ON DELETE CASCADE;


--
-- Name: files_activities; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.files_activities ENABLE ROW LEVEL SECURITY;

--
-- Name: files_activities files_activities_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY files_activities_delete ON public.files_activities FOR DELETE TO appstdio_app USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: files_activities files_activities_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY files_activities_insert ON public.files_activities FOR INSERT TO appstdio_app WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: files_activities files_activities_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY files_activities_select ON public.files_activities FOR SELECT TO appstdio_app USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: files_activities files_activities_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY files_activities_update ON public.files_activities FOR UPDATE TO appstdio_app USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: files_drives; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.files_drives ENABLE ROW LEVEL SECURITY;

--
-- Name: files_drives files_drives_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY files_drives_delete ON public.files_drives FOR DELETE TO appstdio_app USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: files_drives files_drives_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY files_drives_insert ON public.files_drives FOR INSERT TO appstdio_app WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: files_drives files_drives_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY files_drives_select ON public.files_drives FOR SELECT TO appstdio_app USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: files_drives files_drives_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY files_drives_update ON public.files_drives FOR UPDATE TO appstdio_app USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: files_nodes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.files_nodes ENABLE ROW LEVEL SECURITY;

--
-- Name: files_nodes files_nodes_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY files_nodes_delete ON public.files_nodes FOR DELETE TO appstdio_app USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: files_nodes files_nodes_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY files_nodes_insert ON public.files_nodes FOR INSERT TO appstdio_app WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: files_nodes files_nodes_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY files_nodes_select ON public.files_nodes FOR SELECT TO appstdio_app USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: files_nodes files_nodes_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY files_nodes_update ON public.files_nodes FOR UPDATE TO appstdio_app USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: files_permissions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.files_permissions ENABLE ROW LEVEL SECURITY;

--
-- Name: files_permissions files_permissions_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY files_permissions_delete ON public.files_permissions FOR DELETE TO appstdio_app USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: files_permissions files_permissions_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY files_permissions_insert ON public.files_permissions FOR INSERT TO appstdio_app WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: files_permissions files_permissions_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY files_permissions_select ON public.files_permissions FOR SELECT TO appstdio_app USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: files_permissions files_permissions_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY files_permissions_update ON public.files_permissions FOR UPDATE TO appstdio_app USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: files_settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.files_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: files_settings files_settings_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY files_settings_delete ON public.files_settings FOR DELETE TO appstdio_app USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: files_settings files_settings_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY files_settings_insert ON public.files_settings FOR INSERT TO appstdio_app WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: files_settings files_settings_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY files_settings_select ON public.files_settings FOR SELECT TO appstdio_app USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: files_settings files_settings_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY files_settings_update ON public.files_settings FOR UPDATE TO appstdio_app USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: files_versions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.files_versions ENABLE ROW LEVEL SECURITY;

--
-- Name: files_versions files_versions_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY files_versions_delete ON public.files_versions FOR DELETE TO appstdio_app USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: files_versions files_versions_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY files_versions_insert ON public.files_versions FOR INSERT TO appstdio_app WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: files_versions files_versions_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY files_versions_select ON public.files_versions FOR SELECT TO appstdio_app USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: files_versions files_versions_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY files_versions_update ON public.files_versions FOR UPDATE TO appstdio_app USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: group_members; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;

--
-- Name: group_members group_members_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY group_members_delete ON public.group_members FOR DELETE TO appstdio_app USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: group_members group_members_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY group_members_insert ON public.group_members FOR INSERT TO appstdio_app WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: group_members group_members_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY group_members_select ON public.group_members FOR SELECT TO appstdio_app USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: group_members group_members_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY group_members_update ON public.group_members FOR UPDATE TO appstdio_app USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: groups; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;

--
-- Name: groups groups_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY groups_delete ON public.groups FOR DELETE TO appstdio_app USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: groups groups_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY groups_insert ON public.groups FOR INSERT TO appstdio_app WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: groups groups_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY groups_select ON public.groups FOR SELECT TO appstdio_app USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: groups groups_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY groups_update ON public.groups FOR UPDATE TO appstdio_app USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: operators; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.operators ENABLE ROW LEVEL SECURITY;

--
-- Name: tenant_users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tenant_users ENABLE ROW LEVEL SECURITY;

--
-- Name: tenant_users tenant_users_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_users_delete ON public.tenant_users FOR DELETE TO appstdio_app USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: tenant_users tenant_users_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_users_insert ON public.tenant_users FOR INSERT TO appstdio_app WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- Name: tenant_users tenant_users_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_users_select ON public.tenant_users FOR SELECT TO appstdio_app USING (((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid) OR (user_id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::bigint)));


--
-- Name: tenant_users tenant_users_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_users_update ON public.tenant_users FOR UPDATE TO appstdio_app USING ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid)) WITH CHECK ((tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid));


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261006100000'),
('20261005120000'),
('20260929110000'),
('20260929100100'),
('20260929100000'),
('20260928100200'),
('20260928100100'),
('20260928100000'),
('20260910110100'),
('20260910110000'),
('20260909120000'),
('20260904220000'),
('20260904210300'),
('20260904210200'),
('20260904210100'),
('20260904210000');

