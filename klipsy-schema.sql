


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "public"."mood_kind" AS ENUM (
    'huzur',
    'mutlu',
    'heyecan',
    'asik',
    'huzun',
    'ozlem',
    'saskin',
    'sakin',
    'yorgun',
    'dusunce'
);


ALTER TYPE "public"."mood_kind" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."accept_conversation"("conv" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not exists (select 1 from public.conversations c
      where c.id = conv and (auth.uid() = c.user_a or auth.uid() = c.user_b)) then
          raise exception 'Erişimin yok';
            end if;
              update public.conversations set request_state = 'accepted' where id = conv;
              end;
              $$;


ALTER FUNCTION "public"."accept_conversation"("conv" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."are_mutual"("a" "uuid", "b" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (select 1 from public.follows where follower_id = a and followee_id = b)
       and exists (select 1 from public.follows where follower_id = b and followee_id = a);
       $$;


ALTER FUNCTION "public"."are_mutual"("a" "uuid", "b" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auto_hide_check"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
                                                                    declare s public.mod_settings; v_views integer; n_reports integer;
                                                                    begin
                                                                      if new.moment_id is null then return null; end if;
                                                                        select * into s from public.mod_settings where id = 1;
                                                                          select view_count into v_views from public.moments where id = new.moment_id;
                                                                            select count(*) into n_reports from public.reports where moment_id = new.moment_id;
                                                                              if n_reports >= s.hard_cap
                                                                                   or (v_views >= s.min_views and n_reports >= v_views * s.report_ratio)
                                                                                     then
                                                                                         update public.moments set is_removed = true
                                                                                               where id = new.moment_id and is_removed = false;
                                                                                                   update public.reports set status = 'inceleniyor'
                                                                                                         where moment_id = new.moment_id and status = 'bekliyor';
                                                                                                           end if;
                                                                                                             return null;
                                                                                                             end;
                                                                                                             $$;


ALTER FUNCTION "public"."auto_hide_check"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."blok_kontrol"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
                                                  declare
                                                    karsi_taraf uuid;
                                                    begin
                                                      -- mesajın gittiği sohbetteki diğer kişiyi bul
                                                        select case when c.user_a = new.sender_id then c.user_b else c.user_a end
                                                            into karsi_taraf
                                                              from public.conversations c
                                                                where c.id = new.conv_id;

                                                                  if karsi_taraf is null then
                                                                      return new;
                                                                        end if;

                                                                          -- iki yönden biri engelliyse mesaj kaydedilmez
                                                                            if exists (
                                                                                select 1 from public.blocks b
                                                                                    where (b.blocker_id = new.sender_id and b.blocked_id = karsi_taraf)
                                                                                           or (b.blocker_id = karsi_taraf   and b.blocked_id = new.sender_id)
                                                                                             ) then
                                                                                                 raise exception 'engellenmis kullanici';
                                                                                                   end if;

                                                                                                     return new;
                                                                                                     end;
                                                                                                     $$;


ALTER FUNCTION "public"."blok_kontrol"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."bump_comment_count"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
                                                begin
                                                  if tg_op = 'INSERT' then
                                                      update public.moments set comment_count = comment_count + 1 where id = new.moment_id;
                                                        elsif tg_op = 'DELETE' then
                                                            update public.moments set comment_count = greatest(0, comment_count - 1) where id = old.moment_id;
                                                              end if;
                                                                return null;
                                                                end;
                                                                $$;


ALTER FUNCTION "public"."bump_comment_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."bump_comment_like"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
                                                                              begin
                                                                                if tg_op = 'INSERT' then
                                                                                    update public.comments set like_count = like_count + 1 where id = new.comment_id;
                                                                                      elsif tg_op = 'DELETE' then
                                                                                          update public.comments set like_count = greatest(0, like_count - 1) where id = old.comment_id;
                                                                                            end if;
                                                                                              return null;
                                                                                              end;
                                                                                              $$;


ALTER FUNCTION "public"."bump_comment_like"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."bump_follow_counts"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
          begin
            if tg_op = 'INSERT' then
                update public.profiles set following_count = following_count + 1 where id = new.follower_id;
                    update public.profiles set follower_count  = follower_count  + 1 where id = new.followee_id;
                      elsif tg_op = 'DELETE' then
                          update public.profiles set following_count = greatest(0, following_count - 1) where id = old.follower_id;
                              update public.profiles set follower_count  = greatest(0, follower_count  - 1) where id = old.followee_id;
                                end if;
                                  return null;
                                  end;
                                  $$;


ALTER FUNCTION "public"."bump_follow_counts"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."bump_like_count"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
        begin
          if tg_op = 'INSERT' then
              update public.moments set like_count = like_count + 1 where id = new.moment_id;
                elsif tg_op = 'DELETE' then
                    update public.moments set like_count = greatest(0, like_count - 1) where id = old.moment_id;
                      end if;
                        return null;
                        end;
                        $$;


ALTER FUNCTION "public"."bump_like_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."bump_moment_count"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
                                                                        begin
                                                                          if tg_op = 'INSERT' then
                                                                              update public.profiles set moment_count = moment_count + 1 where id = new.author_id;
                                                                                elsif tg_op = 'DELETE' then
                                                                                    update public.profiles set moment_count = greatest(0, moment_count - 1) where id = old.author_id;
                                                                                      end if;
                                                                                        return null;
                                                                                        end;
                                                                                        $$;


ALTER FUNCTION "public"."bump_moment_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."change_username"("yeni" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
begin
  if auth.uid() is null then raise exception 'Giriş yok'; end if;
    if length(yeni) < 3 or length(yeni) > 20 then raise exception 'Kullanıcı adı 3-20 karakter olmalı'; end if;
      if yeni !~ '^[a-z0-9_]+$' then raise exception 'Sadece küçük harf, rakam ve alt çizgi'; end if;
        if exists(select 1 from public.profiles where username = yeni and id <> auth.uid()) then
            raise exception 'Bu kullanıcı adı alınmış';
              end if;
                update public.profiles set username = yeni where id = auth.uid();
                end;
                $_$;


ALTER FUNCTION "public"."change_username"("yeni" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_conversation"("conv" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
                          begin
                            if not exists (select 1 from public.conversations c where c.id = conv and (auth.uid() = c.user_a or auth.uid() = c.user_b)) then
                                raise exception 'Erişimin yok';
                                  end if;
                                    update public.conversations set hidden_for = array_append(hidden_for, auth.uid())
                                        where id = conv and not (auth.uid() = any(hidden_for));
                                          update public.messages set hidden_for = array_append(hidden_for, auth.uid())
                                              where conv_id = conv and not (auth.uid() = any(hidden_for));
                                              end;
                                              $$;


ALTER FUNCTION "public"."delete_conversation"("conv" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_message_all"("msg" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
            declare m public.messages;
            begin
              select * into m from public.messages where id = msg;
                if m.id is null then return; end if;
                  if m.sender_id <> auth.uid() then raise exception 'Sadece kendi mesajını silebilirsin'; end if;
                    update public.messages set deleted_for_all = true, body = null, media_path = null, moment_id = null where id = msg;
                    end;
                    $$;


ALTER FUNCTION "public"."delete_message_all"("msg" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_my_account"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
                                                                                                                                                                                                               declare me uuid := auth.uid();
                                                                                                                                                                                                               begin
                                                                                                                                                                                                                 if me is null then raise exception 'Giriş yapılmamış'; end if;
                                                                                                                                                                                                                   delete from auth.users where id = me;
                                                                                                                                                                                                                   end;
                                                                                                                                                                                                                   $$;


ALTER FUNCTION "public"."delete_my_account"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."edit_message"("msg" "uuid", "yeni" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare m public.messages;
begin
  select * into m from public.messages where id = msg;
    if m.id is null then raise exception 'Mesaj yok'; end if;
      if m.sender_id <> auth.uid() then raise exception 'Sadece kendi mesajını düzenleyebilirsin'; end if;
        if now() - m.created_at > interval '15 minutes' then raise exception 'Düzenleme süresi doldu'; end if;
          if m.deleted_for_all then raise exception 'Silinmiş mesaj düzenlenemez'; end if;
            update public.messages set body = yeni, edited_at = now() where id = msg;
            end;
            $$;


ALTER FUNCTION "public"."edit_message"("msg" "uuid", "yeni" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_comments"("target" "uuid") RETURNS TABLE("id" "uuid", "parent_id" "uuid", "author_id" "uuid", "username" "text", "avatar_url" "text", "body" "text", "like_count" integer, "created_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
                                                                                                                            select c.id, c.parent_id, c.author_id, p.username, p.avatar_url,
                                                                                                                                c.body, c.like_count, c.created_at
                                                                                                                                  from public.comments c
                                                                                                                                    join public.profiles p on p.id = c.author_id
                                                                                                                                      where c.moment_id = target and c.is_removed = false
                                                                                                                                        order by c.created_at asc;
                                                                                                                                        $$;


ALTER FUNCTION "public"."get_comments"("target" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_conversations"() RETURNS TABLE("conv_id" "uuid", "other_id" "uuid", "other_username" "text", "other_avatar" "text", "last_body" "text", "last_kind" "text", "last_at" timestamp with time zone, "unread" integer, "request_state" "text", "requester_id" "uuid")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
        select c.id, other.id, other.username, other.avatar_url,
            lm.body, lm.kind, c.last_message_at,
                (select count(*)::integer from public.messages m
                      where m.conv_id = c.id and m.sender_id <> auth.uid() and m.is_seen = false
                            and not (auth.uid() = any(m.hidden_for))),
                                c.request_state, c.requester_id
                                  from public.conversations c
                                    join public.profiles other
                                        on other.id = case when c.user_a = auth.uid() then c.user_b else c.user_a end
                                          left join lateral (
                                              select body, kind from public.messages
                                                  where conv_id = c.id and not (auth.uid() = any(hidden_for))
                                                      order by created_at desc limit 1
                                                        ) lm on true
                                                          where (auth.uid() = c.user_a or auth.uid() = c.user_b)
                                                              and not (auth.uid() = any(c.hidden_for))
                                                                order by c.last_message_at desc;
                                                                $$;


ALTER FUNCTION "public"."get_conversations"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_feed"("before_time" timestamp with time zone DEFAULT NULL::timestamp with time zone, "page_size" integer DEFAULT 20) RETURNS TABLE("id" "uuid", "author_id" "uuid", "username" "text", "avatar_url" "text", "media_path" "text", "media_kind" "text", "poster_path" "text", "duration_ms" integer, "mood" "public"."mood_kind", "note" "text", "place_label" "text", "like_count" integer, "comment_count" integer, "view_count" integer, "created_at" timestamp with time zone, "song_title" "text", "song_artist" "text", "song_art" "text", "song_preview" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
                                                                                                                           select m.id, m.author_id, p.username, p.avatar_url,
                                                                                                                                    m.media_path, m.media_kind, m.poster_path, m.duration_ms,
                                                                                                                                             m.mood, m.note, m.place_label,
                                                                                                                                                      m.like_count, m.comment_count, m.view_count, m.created_at,
                                                                                                                                                               m.song_title, m.song_artist, m.song_art, m.song_preview
                                                                                                                                                                 from public.moments m
                                                                                                                                                                   join public.profiles p on p.id = m.author_id
                                                                                                                                                                     where m.is_removed = false
                                                                                                                                                                         and p.is_banned  = false
                                                                                                                                                                             and (before_time is null or m.created_at < before_time)
                                                                                                                                                                                 and not exists (
                                                                                                                                                                                       select 1 from public.blocks b
                                                                                                                                                                                             where (b.blocker_id = auth.uid()  and b.blocked_id = m.author_id)
                                                                                                                                                                                                      or (b.blocker_id = m.author_id and b.blocked_id = auth.uid())
                                                                                                                                                                                                          )
                                                                                                                                                                                                            order by m.created_at desc
                                                                                                                                                                                                              limit least(page_size, 50);
                                                                                                                                                                                                              $$;


ALTER FUNCTION "public"."get_feed"("before_time" timestamp with time zone, "page_size" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_messages"("conv" "uuid") RETURNS TABLE("id" "uuid", "sender_id" "uuid", "kind" "text", "body" "text", "media_path" "text", "moment_id" "uuid", "is_seen" boolean, "created_at" timestamp with time zone, "edited_at" timestamp with time zone, "deleted_for_all" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
                                                    begin
                                                      if not exists (select 1 from public.conversations c
                                                          where c.id = conv and (auth.uid() = c.user_a or auth.uid() = c.user_b)) then
                                                              raise exception 'Bu sohbete erişimin yok';
                                                                end if;
                                                                  update public.messages m set is_seen = true
                                                                      where m.conv_id = conv and m.sender_id <> auth.uid() and m.is_seen = false;
                                                                        return query
                                                                            select m.id, m.sender_id, m.kind, m.body, m.media_path,
                                                                                       m.moment_id, m.is_seen, m.created_at, m.edited_at, m.deleted_for_all
                                                                                           from public.messages m
                                                                                               where m.conv_id = conv and not (auth.uid() = any(m.hidden_for))
                                                                                                   order by m.created_at asc;
                                                                                                   end;
                                                                                                   $$;


ALTER FUNCTION "public"."get_messages"("conv" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_notifications"() RETURNS TABLE("id" "uuid", "kind" "text", "actor_id" "uuid", "actor_username" "text", "actor_avatar" "text", "moment_id" "uuid", "moment_media" "text", "comment_body" "text", "is_seen" boolean, "created_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
                                                                                                              select n.id, n.kind, n.actor_id, a.username, a.avatar_url,
                                                                                                                  n.moment_id, m.media_path, c.body, n.is_seen, n.created_at
                                                                                                                    from public.notifications n
                                                                                                                      join public.profiles a on a.id = n.actor_id
                                                                                                                        left join public.moments m on m.id = n.moment_id
                                                                                                                          left join public.comments c on c.id = n.comment_id
                                                                                                                            where n.user_id = auth.uid()
                                                                                                                              order by n.created_at desc limit 100;
                                                                                                                              $$;


ALTER FUNCTION "public"."get_notifications"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_saved"() RETURNS TABLE("id" "uuid", "author_id" "uuid", "author_username" "text", "author_avatar" "text", "media_path" "text", "media_kind" "text", "poster_path" "text", "mood" "text", "note" "text", "place_label" "text", "geo_lat" numeric, "geo_lng" numeric, "like_count" integer, "comment_count" integer, "view_count" integer, "created_at" timestamp with time zone, "song_title" "text", "song_artist" "text", "song_art" "text", "song_preview" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
                                                                                                                                                                                                                          select m.id, m.author_id, p.username, p.avatar_url,
                                                                                                                                                                                                                                   m.media_path, m.media_kind, m.poster_path, m.mood::text, m.note,
                                                                                                                                                                                                                                            m.place_label, m.geo_lat, m.geo_lng,
                                                                                                                                                                                                                                                     m.like_count, m.comment_count, m.view_count, m.created_at,
                                                                                                                                                                                                                                                              m.song_title, m.song_artist, m.song_art, m.song_preview
                                                                                                                                                                                                                                                                from public.saves s
                                                                                                                                                                                                                                                                  join public.moments  m on m.id = s.moment_id
                                                                                                                                                                                                                                                                    join public.profiles p on p.id = m.author_id
                                                                                                                                                                                                                                                                      where s.user_id = auth.uid()
                                                                                                                                                                                                                                                                          and m.is_removed = false
                                                                                                                                                                                                                                                                            order by s.created_at desc;
                                                                                                                                                                                                                                                                            $$;


ALTER FUNCTION "public"."get_saved"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
                                      declare
                                        wanted text;
                                          final  text;
                                            n      integer := 0;
                                            begin
                                              wanted := lower(coalesce(new.raw_user_meta_data->>'username', ''));
                                                wanted := regexp_replace(wanted, '[^a-z0-9._]', '', 'g');
                                                  if char_length(wanted) < 3 then
                                                      wanted := 'kullanici' || substr(replace(new.id::text, '-', ''), 1, 6);
                                                        end if;
                                                          wanted := substr(wanted, 1, 20);
                                                            final  := wanted;
                                                              while exists (select 1 from public.profiles p where lower(p.username) = final) loop
                                                                  n := n + 1;
                                                                      final := substr(wanted, 1, 17) || n::text;
                                                                        end loop;
                                                                          insert into public.profiles (id, username) values (new.id, final);
                                                                            return new;
                                                                            end;
                                                                            $$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."hide_message"("msg" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
                    begin
                      update public.messages set hidden_for = array_append(hidden_for, auth.uid())
                          where id = msg and not (auth.uid() = any(hidden_for));
                          end;
                          $$;


ALTER FUNCTION "public"."hide_message"("msg" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_following"("target" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
                                                                                                                                          select exists (
                                                                                                                                              select 1 from public.follows
                                                                                                                                                  where follower_id = auth.uid() and followee_id = target
                                                                                                                                                    );
                                                                                                                                                    $$;


ALTER FUNCTION "public"."is_following"("target" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_all_seen"() RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
                                                                                                                                update public.notifications set is_seen = true
                                                                                                                                    where user_id = auth.uid() and is_seen = false;
                                                                                                                                    $$;


ALTER FUNCTION "public"."mark_all_seen"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_view"("target" "uuid") RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
                                                                                                                  update public.moments set view_count = view_count + 1
                                                                                                                      where id = target and is_removed = false;
                                                                                                                      $$;


ALTER FUNCTION "public"."mark_view"("target" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mod_ban_user"("target" "uuid") RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
                                                                                                                                                                                                                         update public.profiles set is_banned = true where id = target;
                                                                                                                                                                                                                         $$;


ALTER FUNCTION "public"."mod_ban_user"("target" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mod_remove_moment"("target" "uuid") RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
                                                                                                                                                                                                                       update public.moments set is_removed = true where id = target;
                                                                                                                                                                                                                       $$;


ALTER FUNCTION "public"."mod_remove_moment"("target" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mod_restore_moment"("target" "uuid") RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
                                                                                                                                                                                                                     update public.moments set is_removed = false where id = target;
                                                                                                                                                                                                                     $$;


ALTER FUNCTION "public"."mod_restore_moment"("target" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_on_comment"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
                                                                              declare owner_id uuid;
                                                                              begin
                                                                                select author_id into owner_id from public.moments where id = new.moment_id;
                                                                                  if owner_id is not null and owner_id <> new.author_id then
                                                                                      insert into public.notifications (user_id, actor_id, kind, moment_id, comment_id)
                                                                                          values (owner_id, new.author_id, 'comment', new.moment_id, new.id);
                                                                                            end if;
                                                                                              return null;
                                                                                              end;
                                                                                              $$;


ALTER FUNCTION "public"."notify_on_comment"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_on_follow"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
                                                                                                begin
                                                                                                  insert into public.notifications (user_id, actor_id, kind)
                                                                                                    values (new.followee_id, new.follower_id, 'follow');
                                                                                                      return null;
                                                                                                      end;
                                                                                                      $$;


ALTER FUNCTION "public"."notify_on_follow"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_on_like"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
                                                            declare owner_id uuid;
                                                            begin
                                                              select author_id into owner_id from public.moments where id = new.moment_id;
                                                                if owner_id is not null and owner_id <> new.user_id then
                                                                    insert into public.notifications (user_id, actor_id, kind, moment_id)
                                                                        values (owner_id, new.user_id, 'like', new.moment_id);
                                                                          end if;
                                                                            return null;
                                                                            end;
                                                                            $$;


ALTER FUNCTION "public"."notify_on_like"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."on_block"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
                                                                                                                             begin
                                                                                                                               delete from public.follows
                                                                                                                                   where (follower_id = new.blocker_id and followee_id = new.blocked_id)
                                                                                                                                          or (follower_id = new.blocked_id and followee_id = new.blocker_id);
                                                                                                                                            return null;
                                                                                                                                            end;
                                                                                                                                            $$;


ALTER FUNCTION "public"."on_block"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."protect_profile_counters"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  -- sadece normal kullanıcı DOĞRUDAN profil güncellerken sayaçları kilitle.
    -- trigger'ların (security definer) yaptığı güncellemeler auth.uid()=null ile gelir, onlara dokunma.
      if auth.uid() is not null and auth.uid() = new.id then
          new.follower_count  := old.follower_count;
              new.following_count := old.following_count;
                  new.moment_count    := old.moment_count;
                      new.is_banned       := old.is_banned;
                        end if;
                          return new;
                          end;
                          $$;


ALTER FUNCTION "public"."protect_profile_counters"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."remove_follower"("follower" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if auth.uid() is null then raise exception 'Giriş yok'; end if;
    delete from public.follows
        where follower_id = follower and followee_id = auth.uid();
        end;
        $$;


ALTER FUNCTION "public"."remove_follower"("follower" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."round_geo"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
                                                              begin
                                                                if new.geo_lat is not null then new.geo_lat := round(new.geo_lat, 3); end if;
                                                                  if new.geo_lng is not null then new.geo_lng := round(new.geo_lng, 3); end if;
                                                                    return new;
                                                                    end;
                                                                    $$;


ALTER FUNCTION "public"."round_geo"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."send_message"("to_user" "uuid", "msg_kind" "text" DEFAULT 'text'::"text", "msg_body" "text" DEFAULT NULL::"text", "msg_media" "text" DEFAULT NULL::"text", "msg_moment" "uuid" DEFAULT NULL::"uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
    declare me uuid := auth.uid(); lo uuid; hi uuid; conv uuid; new_msg uuid; mutual boolean;
    begin
      if me is null then raise exception 'Giriş yapılmamış'; end if;
        if me = to_user then raise exception 'Kendine mesaj gönderemezsin'; end if;

          mutual := public.are_mutual(me, to_user);

            if me < to_user then lo := me; hi := to_user; else lo := to_user; hi := me; end if;
              select id into conv from public.conversations where user_a = lo and user_b = hi;

                if conv is null then
                    -- yeni sohbet: karşılıklı takip yoksa istek olarak aç
                        insert into public.conversations (user_a, user_b, request_state, requester_id)
                              values (lo, hi, case when mutual then 'none' else 'pending' end, case when mutual then null else me end)
                                    returning id into conv;
                                      end if;

                                        insert into public.messages (conv_id, sender_id, kind, body, media_path, moment_id)
                                            values (conv, me, msg_kind, msg_body, msg_media, msg_moment) returning id into new_msg;
                                              update public.conversations set last_message_at = now() where id = conv;
                                                return new_msg;
                                                end;
                                                $$;


ALTER FUNCTION "public"."send_message"("to_user" "uuid", "msg_kind" "text", "msg_body" "text", "msg_media" "text", "msg_moment" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."touch_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
                              begin
                                new.updated_at = now();
                                  return new;
                                  end;
                                  $$;


ALTER FUNCTION "public"."touch_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."unread_messages"() RETURNS integer
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
                                                                                                                                                                                    select count(*)::integer from public.messages m
                                                                                                                                                                                      join public.conversations c on c.id = m.conv_id
                                                                                                                                                                                        where (auth.uid() = c.user_a or auth.uid() = c.user_b)
                                                                                                                                                                                            and m.sender_id <> auth.uid() and m.is_seen = false;
                                                                                                                                                                                            $$;


ALTER FUNCTION "public"."unread_messages"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."unseen_count"() RETURNS integer
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
                                                                                                                                      select count(*)::integer from public.notifications
                                                                                                                                        where user_id = auth.uid() and is_seen = false;
                                                                                                                                        $$;


ALTER FUNCTION "public"."unseen_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."username_available"("candidate" "text") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
                                                                                                                                  select not exists (
                                                                                                                                      select 1 from public.profiles where lower(username) = lower(candidate)
                                                                                                                                        );
                                                                                                                                        $$;


ALTER FUNCTION "public"."username_available"("candidate" "text") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."blocks" (
    "blocker_id" "uuid" NOT NULL,
    "blocked_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "kendini_engelleyemez" CHECK (("blocker_id" <> "blocked_id"))
);


ALTER TABLE "public"."blocks" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."comment_likes" (
    "comment_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL
);


ALTER TABLE "public"."comment_likes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."comments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "moment_id" "uuid" NOT NULL,
    "author_id" "uuid" NOT NULL,
    "parent_id" "uuid",
    "body" "text" NOT NULL,
    "like_count" integer DEFAULT 0 NOT NULL,
    "is_removed" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "body_length" CHECK ((("char_length"("body") >= 1) AND ("char_length"("body") <= 240)))
);


ALTER TABLE "public"."comments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."conversations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_a" "uuid" NOT NULL,
    "user_b" "uuid" NOT NULL,
    "last_message_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "hidden_for" "uuid"[] DEFAULT '{}'::"uuid"[] NOT NULL,
    "request_state" "text" DEFAULT 'none'::"text" NOT NULL,
    "requester_id" "uuid",
    CONSTRAINT "konusan_sirasi" CHECK (("user_a" < "user_b"))
);


ALTER TABLE "public"."conversations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."follows" (
    "follower_id" "uuid" NOT NULL,
    "followee_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "kendini_takip_edemez" CHECK (("follower_id" <> "followee_id"))
);


ALTER TABLE "public"."follows" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."likes" (
    "moment_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."likes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "conv_id" "uuid" NOT NULL,
    "sender_id" "uuid" NOT NULL,
    "kind" "text" DEFAULT 'text'::"text" NOT NULL,
    "body" "text",
    "media_path" "text",
    "moment_id" "uuid",
    "is_seen" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "edited_at" timestamp with time zone,
    "deleted_for_all" boolean DEFAULT false NOT NULL,
    "hidden_for" "uuid"[] DEFAULT '{}'::"uuid"[] NOT NULL,
    CONSTRAINT "body_length" CHECK ((("body" IS NULL) OR ("char_length"("body") <= 1000))),
    CONSTRAINT "messages_kind_check" CHECK (("kind" = ANY (ARRAY['text'::"text", 'media'::"text", 'moment'::"text"])))
);


ALTER TABLE "public"."messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mod_settings" (
    "id" integer DEFAULT 1 NOT NULL,
    "min_views" integer DEFAULT 1000 NOT NULL,
    "report_ratio" numeric DEFAULT 0.10 NOT NULL,
    "hard_cap" integer DEFAULT 200 NOT NULL,
    CONSTRAINT "tek_satir" CHECK (("id" = 1))
);


ALTER TABLE "public"."mod_settings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."moments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "author_id" "uuid" NOT NULL,
    "media_path" "text" NOT NULL,
    "media_kind" "text" DEFAULT 'photo'::"text" NOT NULL,
    "duration_ms" integer,
    "mood" "public"."mood_kind" NOT NULL,
    "note" "text",
    "place_label" "text",
    "geo_lat" numeric(6,3),
    "geo_lng" numeric(6,3),
    "like_count" integer DEFAULT 0 NOT NULL,
    "comment_count" integer DEFAULT 0 NOT NULL,
    "view_count" integer DEFAULT 0 NOT NULL,
    "is_removed" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "song_title" "text",
    "song_artist" "text",
    "song_art" "text",
    "song_preview" "text",
    "poster_path" "text",
    CONSTRAINT "duration_limit" CHECK ((("duration_ms" IS NULL) OR ("duration_ms" <= 30000))),
    CONSTRAINT "moments_media_kind_check" CHECK (("media_kind" = ANY (ARRAY['photo'::"text", 'video'::"text"]))),
    CONSTRAINT "note_length" CHECK ((("note" IS NULL) OR ("char_length"("note") <= 180)))
);


ALTER TABLE "public"."moments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "actor_id" "uuid" NOT NULL,
    "kind" "text" NOT NULL,
    "moment_id" "uuid",
    "comment_id" "uuid",
    "is_seen" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "notifications_kind_check" CHECK (("kind" = ANY (ARRAY['like'::"text", 'comment'::"text", 'follow'::"text"])))
);


ALTER TABLE "public"."notifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "username" "text" NOT NULL,
    "avatar_url" "text",
    "avatar_taken_at" timestamp with time zone,
    "bio" "text",
    "moment_count" integer DEFAULT 0 NOT NULL,
    "follower_count" integer DEFAULT 0 NOT NULL,
    "following_count" integer DEFAULT 0 NOT NULL,
    "is_banned" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "notif_enabled" boolean DEFAULT true NOT NULL,
    "share_location" boolean DEFAULT true NOT NULL,
    "display_name" "text",
    "city" "text",
    "education" "text",
    "job" "text",
    "zodiac" "text",
    "interests" "text",
    "link" "text",
    "onboarded" boolean DEFAULT false NOT NULL,
    "gender" "text",
    CONSTRAINT "bio_length" CHECK ((("bio" IS NULL) OR ("char_length"("bio") <= 160))),
    CONSTRAINT "username_format" CHECK (("username" ~ '^[a-z0-9._]{3,20}$'::"text"))
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."reports" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "reporter_id" "uuid" NOT NULL,
    "target_type" "text" NOT NULL,
    "moment_id" "uuid",
    "comment_id" "uuid",
    "user_id" "uuid",
    "reason" "text" NOT NULL,
    "detail" "text",
    "status" "text" DEFAULT 'bekliyor'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "detail_length" CHECK ((("detail" IS NULL) OR ("char_length"("detail") <= 500))),
    CONSTRAINT "reports_reason_check" CHECK (("reason" = ANY (ARRAY['spam'::"text", 'taciz'::"text", 'siddet'::"text", 'cinsel'::"text", 'nefret'::"text", 'yaniltici'::"text", 'telif'::"text", 'diger'::"text"]))),
    CONSTRAINT "reports_status_check" CHECK (("status" = ANY (ARRAY['bekliyor'::"text", 'inceleniyor'::"text", 'kaldirildi'::"text", 'reddedildi'::"text"]))),
    CONSTRAINT "reports_target_type_check" CHECK (("target_type" = ANY (ARRAY['moment'::"text", 'comment'::"text", 'user'::"text"])))
);


ALTER TABLE "public"."reports" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."saves" (
    "moment_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."saves" OWNER TO "postgres";


ALTER TABLE ONLY "public"."blocks"
    ADD CONSTRAINT "blocks_pkey" PRIMARY KEY ("blocker_id", "blocked_id");



ALTER TABLE ONLY "public"."comment_likes"
    ADD CONSTRAINT "comment_likes_pkey" PRIMARY KEY ("comment_id", "user_id");



ALTER TABLE ONLY "public"."comments"
    ADD CONSTRAINT "comments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_user_a_user_b_key" UNIQUE ("user_a", "user_b");



ALTER TABLE ONLY "public"."follows"
    ADD CONSTRAINT "follows_pkey" PRIMARY KEY ("follower_id", "followee_id");



ALTER TABLE ONLY "public"."likes"
    ADD CONSTRAINT "likes_pkey" PRIMARY KEY ("moment_id", "user_id");



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."mod_settings"
    ADD CONSTRAINT "mod_settings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."moments"
    ADD CONSTRAINT "moments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_reporter_id_moment_id_key" UNIQUE ("reporter_id", "moment_id");



ALTER TABLE ONLY "public"."saves"
    ADD CONSTRAINT "saves_pkey" PRIMARY KEY ("moment_id", "user_id");



CREATE INDEX "blocks_blocked_idx" ON "public"."blocks" USING "btree" ("blocked_id");



CREATE INDEX "comments_moment_idx" ON "public"."comments" USING "btree" ("moment_id", "created_at") WHERE ("is_removed" = false);



CREATE INDEX "comments_parent_idx" ON "public"."comments" USING "btree" ("parent_id", "created_at");



CREATE INDEX "conversations_a_idx" ON "public"."conversations" USING "btree" ("user_a", "last_message_at" DESC);



CREATE INDEX "conversations_b_idx" ON "public"."conversations" USING "btree" ("user_b", "last_message_at" DESC);



CREATE INDEX "follows_followee_idx" ON "public"."follows" USING "btree" ("followee_id", "created_at" DESC);



CREATE INDEX "follows_follower_idx" ON "public"."follows" USING "btree" ("follower_id", "created_at" DESC);



CREATE INDEX "likes_user_idx" ON "public"."likes" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "messages_conv_idx" ON "public"."messages" USING "btree" ("conv_id", "created_at");



CREATE INDEX "moments_author_idx" ON "public"."moments" USING "btree" ("author_id", "created_at" DESC);



CREATE INDEX "moments_created_idx" ON "public"."moments" USING "btree" ("created_at" DESC) WHERE ("is_removed" = false);



CREATE INDEX "moments_feed_idx" ON "public"."moments" USING "btree" ("created_at" DESC) WHERE ("is_removed" = false);



CREATE INDEX "notifications_unseen_idx" ON "public"."notifications" USING "btree" ("user_id") WHERE ("is_seen" = false);



CREATE INDEX "notifications_user_idx" ON "public"."notifications" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "profiles_created_at_idx" ON "public"."profiles" USING "btree" ("created_at" DESC);



CREATE UNIQUE INDEX "profiles_username_key" ON "public"."profiles" USING "btree" ("lower"("username"));



CREATE INDEX "reports_moment_idx" ON "public"."reports" USING "btree" ("moment_id");



CREATE INDEX "reports_status_idx" ON "public"."reports" USING "btree" ("status", "created_at" DESC);



CREATE INDEX "saves_user_idx" ON "public"."saves" USING "btree" ("user_id", "created_at" DESC);



CREATE OR REPLACE TRIGGER "blocks_cut_follows" AFTER INSERT ON "public"."blocks" FOR EACH ROW EXECUTE FUNCTION "public"."on_block"();



CREATE OR REPLACE TRIGGER "comment_likes_bump" AFTER INSERT OR DELETE ON "public"."comment_likes" FOR EACH ROW EXECUTE FUNCTION "public"."bump_comment_like"();



CREATE OR REPLACE TRIGGER "comment_notify" AFTER INSERT ON "public"."comments" FOR EACH ROW EXECUTE FUNCTION "public"."notify_on_comment"();



CREATE OR REPLACE TRIGGER "comments_bump_count" AFTER INSERT OR DELETE ON "public"."comments" FOR EACH ROW EXECUTE FUNCTION "public"."bump_comment_count"();



CREATE OR REPLACE TRIGGER "follow_notify" AFTER INSERT ON "public"."follows" FOR EACH ROW EXECUTE FUNCTION "public"."notify_on_follow"();



CREATE OR REPLACE TRIGGER "follows_bump_counts" AFTER INSERT OR DELETE ON "public"."follows" FOR EACH ROW EXECUTE FUNCTION "public"."bump_follow_counts"();



CREATE OR REPLACE TRIGGER "like_notify" AFTER INSERT ON "public"."likes" FOR EACH ROW EXECUTE FUNCTION "public"."notify_on_like"();



CREATE OR REPLACE TRIGGER "likes_bump_count" AFTER INSERT OR DELETE ON "public"."likes" FOR EACH ROW EXECUTE FUNCTION "public"."bump_like_count"();



CREATE OR REPLACE TRIGGER "messages_blok_kontrol" BEFORE INSERT ON "public"."messages" FOR EACH ROW EXECUTE FUNCTION "public"."blok_kontrol"();



CREATE OR REPLACE TRIGGER "moments_bump_count" AFTER INSERT OR DELETE ON "public"."moments" FOR EACH ROW EXECUTE FUNCTION "public"."bump_moment_count"();



CREATE OR REPLACE TRIGGER "moments_round_geo" BEFORE INSERT OR UPDATE ON "public"."moments" FOR EACH ROW EXECUTE FUNCTION "public"."round_geo"();



CREATE OR REPLACE TRIGGER "profiles_protect_counters" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."protect_profile_counters"();



CREATE OR REPLACE TRIGGER "profiles_touch_updated_at" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "reports_auto_hide" AFTER INSERT ON "public"."reports" FOR EACH ROW EXECUTE FUNCTION "public"."auto_hide_check"();



ALTER TABLE ONLY "public"."blocks"
    ADD CONSTRAINT "blocks_blocked_id_fkey" FOREIGN KEY ("blocked_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."blocks"
    ADD CONSTRAINT "blocks_blocker_id_fkey" FOREIGN KEY ("blocker_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."comment_likes"
    ADD CONSTRAINT "comment_likes_comment_id_fkey" FOREIGN KEY ("comment_id") REFERENCES "public"."comments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."comment_likes"
    ADD CONSTRAINT "comment_likes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."comments"
    ADD CONSTRAINT "comments_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."comments"
    ADD CONSTRAINT "comments_moment_id_fkey" FOREIGN KEY ("moment_id") REFERENCES "public"."moments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."comments"
    ADD CONSTRAINT "comments_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "public"."comments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_user_a_fkey" FOREIGN KEY ("user_a") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_user_b_fkey" FOREIGN KEY ("user_b") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."follows"
    ADD CONSTRAINT "follows_followee_id_fkey" FOREIGN KEY ("followee_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."follows"
    ADD CONSTRAINT "follows_follower_id_fkey" FOREIGN KEY ("follower_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."likes"
    ADD CONSTRAINT "likes_moment_id_fkey" FOREIGN KEY ("moment_id") REFERENCES "public"."moments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."likes"
    ADD CONSTRAINT "likes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_conv_id_fkey" FOREIGN KEY ("conv_id") REFERENCES "public"."conversations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_moment_id_fkey" FOREIGN KEY ("moment_id") REFERENCES "public"."moments"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_sender_id_fkey" FOREIGN KEY ("sender_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."moments"
    ADD CONSTRAINT "moments_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_comment_id_fkey" FOREIGN KEY ("comment_id") REFERENCES "public"."comments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_moment_id_fkey" FOREIGN KEY ("moment_id") REFERENCES "public"."moments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_comment_id_fkey" FOREIGN KEY ("comment_id") REFERENCES "public"."comments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_moment_id_fkey" FOREIGN KEY ("moment_id") REFERENCES "public"."moments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_reporter_id_fkey" FOREIGN KEY ("reporter_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reports"
    ADD CONSTRAINT "reports_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."saves"
    ADD CONSTRAINT "saves_moment_id_fkey" FOREIGN KEY ("moment_id") REFERENCES "public"."moments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."saves"
    ADD CONSTRAINT "saves_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



CREATE POLICY "anlar herkese gorunur" ON "public"."moments" FOR SELECT USING ((("is_removed" = false) OR ("author_id" = "auth"."uid"())));



CREATE POLICY "ayarlar okunur" ON "public"."mod_settings" FOR SELECT USING (true);



CREATE POLICY "begeniler gorunur" ON "public"."likes" FOR SELECT USING (true);



ALTER TABLE "public"."blocks" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "blocks_own" ON "public"."blocks" TO "authenticated" USING (("blocker_id" = "auth"."uid"())) WITH CHECK (("blocker_id" = "auth"."uid"()));



ALTER TABLE "public"."comment_likes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."comments" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "comments_delete_own" ON "public"."comments" FOR DELETE TO "authenticated" USING ((("author_id" = "auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "public"."moments" "m"
  WHERE (("m"."id" = "comments"."moment_id") AND ("m"."author_id" = "auth"."uid"()))))));



ALTER TABLE "public"."conversations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."follows" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "kendi anini paylas" ON "public"."moments" FOR INSERT TO "authenticated" WITH CHECK (("author_id" = "auth"."uid"()));



CREATE POLICY "kendi anini sil" ON "public"."moments" FOR DELETE TO "authenticated" USING (("author_id" = "auth"."uid"()));



CREATE POLICY "kendi begenini ekle" ON "public"."likes" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "kendi begenini kaldir" ON "public"."likes" FOR DELETE TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "kendi bildirimlerini gor" ON "public"."notifications" FOR SELECT USING (("user_id" = "auth"."uid"()));



CREATE POLICY "kendi kaydini ekle" ON "public"."saves" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "kendi kaydini kaldir" ON "public"."saves" FOR DELETE TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "kendi kayitlarini gor" ON "public"."saves" FOR SELECT USING (("user_id" = "auth"."uid"()));



CREATE POLICY "kendi mesajini sil" ON "public"."messages" FOR DELETE TO "authenticated" USING (("sender_id" = "auth"."uid"()));



CREATE POLICY "kendi mesajlarini gor" ON "public"."messages" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."conversations" "c"
  WHERE (("c"."id" = "messages"."conv_id") AND (("auth"."uid"() = "c"."user_a") OR ("auth"."uid"() = "c"."user_b"))))));



CREATE POLICY "kendi profilini gunceller" ON "public"."profiles" FOR UPDATE USING (("auth"."uid"() = "id")) WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "kendi sikayetini gor" ON "public"."reports" FOR SELECT USING (("reporter_id" = "auth"."uid"()));



CREATE POLICY "kendi sohbetlerini gor" ON "public"."conversations" FOR SELECT USING ((("auth"."uid"() = "user_a") OR ("auth"."uid"() = "user_b")));



CREATE POLICY "kendi takibini birak" ON "public"."follows" FOR DELETE TO "authenticated" USING (("follower_id" = "auth"."uid"()));



CREATE POLICY "kendi takibini ekle" ON "public"."follows" FOR INSERT TO "authenticated" WITH CHECK (("follower_id" = "auth"."uid"()));



CREATE POLICY "kendi yorum begenini ekle" ON "public"."comment_likes" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "kendi yorum begenini kaldir" ON "public"."comment_likes" FOR DELETE TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "kendi yorumunu ekle" ON "public"."comments" FOR INSERT TO "authenticated" WITH CHECK (("author_id" = "auth"."uid"()));



ALTER TABLE "public"."likes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "mesaji okundu yap" ON "public"."messages" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."conversations" "c"
  WHERE (("c"."id" = "messages"."conv_id") AND (("auth"."uid"() = "c"."user_a") OR ("auth"."uid"() = "c"."user_b"))))));



ALTER TABLE "public"."messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."mod_settings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."moments" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "notif_update_own" ON "public"."notifications" FOR UPDATE TO "authenticated" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



ALTER TABLE "public"."notifications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiller herkese gorunur" ON "public"."profiles" FOR SELECT USING (true);



CREATE POLICY "public_wall_read" ON "public"."moments" FOR SELECT TO "anon" USING (("is_removed" = false));



ALTER TABLE "public"."reports" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."saves" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sikayet ac" ON "public"."reports" FOR INSERT TO "authenticated" WITH CHECK (("reporter_id" = "auth"."uid"()));



CREATE POLICY "takipler gorunur" ON "public"."follows" FOR SELECT USING (true);



CREATE POLICY "yorum begenileri gorunur" ON "public"."comment_likes" FOR SELECT USING (true);



CREATE POLICY "yorumlar gorunur" ON "public"."comments" FOR SELECT USING ((("is_removed" = false) OR ("author_id" = "auth"."uid"())));





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."messages";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."notifications";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";






















































































































































GRANT ALL ON FUNCTION "public"."accept_conversation"("conv" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."accept_conversation"("conv" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."accept_conversation"("conv" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."are_mutual"("a" "uuid", "b" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."are_mutual"("a" "uuid", "b" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."are_mutual"("a" "uuid", "b" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."auto_hide_check"() TO "anon";
GRANT ALL ON FUNCTION "public"."auto_hide_check"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_hide_check"() TO "service_role";



GRANT ALL ON FUNCTION "public"."blok_kontrol"() TO "anon";
GRANT ALL ON FUNCTION "public"."blok_kontrol"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."blok_kontrol"() TO "service_role";



GRANT ALL ON FUNCTION "public"."bump_comment_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."bump_comment_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."bump_comment_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."bump_comment_like"() TO "anon";
GRANT ALL ON FUNCTION "public"."bump_comment_like"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."bump_comment_like"() TO "service_role";



GRANT ALL ON FUNCTION "public"."bump_follow_counts"() TO "anon";
GRANT ALL ON FUNCTION "public"."bump_follow_counts"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."bump_follow_counts"() TO "service_role";



GRANT ALL ON FUNCTION "public"."bump_like_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."bump_like_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."bump_like_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."bump_moment_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."bump_moment_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."bump_moment_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."change_username"("yeni" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."change_username"("yeni" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."change_username"("yeni" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_conversation"("conv" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."delete_conversation"("conv" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_conversation"("conv" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_message_all"("msg" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."delete_message_all"("msg" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_message_all"("msg" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_my_account"() TO "anon";
GRANT ALL ON FUNCTION "public"."delete_my_account"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_my_account"() TO "service_role";



GRANT ALL ON FUNCTION "public"."edit_message"("msg" "uuid", "yeni" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."edit_message"("msg" "uuid", "yeni" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."edit_message"("msg" "uuid", "yeni" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_comments"("target" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_comments"("target" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_comments"("target" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_conversations"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_conversations"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_conversations"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_feed"("before_time" timestamp with time zone, "page_size" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_feed"("before_time" timestamp with time zone, "page_size" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_feed"("before_time" timestamp with time zone, "page_size" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_messages"("conv" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_messages"("conv" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_messages"("conv" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_notifications"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_notifications"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_notifications"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_saved"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_saved"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_saved"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."hide_message"("msg" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."hide_message"("msg" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hide_message"("msg" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_following"("target" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_following"("target" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_following"("target" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."mark_all_seen"() TO "anon";
GRANT ALL ON FUNCTION "public"."mark_all_seen"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_all_seen"() TO "service_role";



GRANT ALL ON FUNCTION "public"."mark_view"("target" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."mark_view"("target" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_view"("target" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."mod_ban_user"("target" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."mod_ban_user"("target" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mod_ban_user"("target" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."mod_remove_moment"("target" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."mod_remove_moment"("target" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mod_remove_moment"("target" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."mod_restore_moment"("target" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."mod_restore_moment"("target" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mod_restore_moment"("target" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_on_comment"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_on_comment"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_on_comment"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_on_follow"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_on_follow"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_on_follow"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_on_like"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_on_like"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_on_like"() TO "service_role";



GRANT ALL ON FUNCTION "public"."on_block"() TO "anon";
GRANT ALL ON FUNCTION "public"."on_block"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."on_block"() TO "service_role";



GRANT ALL ON FUNCTION "public"."protect_profile_counters"() TO "anon";
GRANT ALL ON FUNCTION "public"."protect_profile_counters"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."protect_profile_counters"() TO "service_role";



GRANT ALL ON FUNCTION "public"."remove_follower"("follower" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."remove_follower"("follower" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."remove_follower"("follower" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."round_geo"() TO "anon";
GRANT ALL ON FUNCTION "public"."round_geo"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."round_geo"() TO "service_role";



GRANT ALL ON FUNCTION "public"."send_message"("to_user" "uuid", "msg_kind" "text", "msg_body" "text", "msg_media" "text", "msg_moment" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."send_message"("to_user" "uuid", "msg_kind" "text", "msg_body" "text", "msg_media" "text", "msg_moment" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."send_message"("to_user" "uuid", "msg_kind" "text", "msg_body" "text", "msg_media" "text", "msg_moment" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."touch_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."touch_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."touch_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."unread_messages"() TO "anon";
GRANT ALL ON FUNCTION "public"."unread_messages"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."unread_messages"() TO "service_role";



GRANT ALL ON FUNCTION "public"."unseen_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."unseen_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."unseen_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."username_available"("candidate" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."username_available"("candidate" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."username_available"("candidate" "text") TO "service_role";


















GRANT ALL ON TABLE "public"."blocks" TO "anon";
GRANT ALL ON TABLE "public"."blocks" TO "authenticated";
GRANT ALL ON TABLE "public"."blocks" TO "service_role";



GRANT ALL ON TABLE "public"."comment_likes" TO "anon";
GRANT ALL ON TABLE "public"."comment_likes" TO "authenticated";
GRANT ALL ON TABLE "public"."comment_likes" TO "service_role";



GRANT ALL ON TABLE "public"."comments" TO "anon";
GRANT ALL ON TABLE "public"."comments" TO "authenticated";
GRANT ALL ON TABLE "public"."comments" TO "service_role";



GRANT ALL ON TABLE "public"."conversations" TO "anon";
GRANT ALL ON TABLE "public"."conversations" TO "authenticated";
GRANT ALL ON TABLE "public"."conversations" TO "service_role";



GRANT ALL ON TABLE "public"."follows" TO "anon";
GRANT ALL ON TABLE "public"."follows" TO "authenticated";
GRANT ALL ON TABLE "public"."follows" TO "service_role";



GRANT ALL ON TABLE "public"."likes" TO "anon";
GRANT ALL ON TABLE "public"."likes" TO "authenticated";
GRANT ALL ON TABLE "public"."likes" TO "service_role";



GRANT ALL ON TABLE "public"."messages" TO "anon";
GRANT ALL ON TABLE "public"."messages" TO "authenticated";
GRANT ALL ON TABLE "public"."messages" TO "service_role";



GRANT ALL ON TABLE "public"."mod_settings" TO "anon";
GRANT ALL ON TABLE "public"."mod_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."mod_settings" TO "service_role";



GRANT ALL ON TABLE "public"."moments" TO "anon";
GRANT ALL ON TABLE "public"."moments" TO "authenticated";
GRANT ALL ON TABLE "public"."moments" TO "service_role";



GRANT ALL ON TABLE "public"."notifications" TO "anon";
GRANT ALL ON TABLE "public"."notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."notifications" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."reports" TO "anon";
GRANT ALL ON TABLE "public"."reports" TO "authenticated";
GRANT ALL ON TABLE "public"."reports" TO "service_role";



GRANT ALL ON TABLE "public"."saves" TO "anon";
GRANT ALL ON TABLE "public"."saves" TO "authenticated";
GRANT ALL ON TABLE "public"."saves" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";































