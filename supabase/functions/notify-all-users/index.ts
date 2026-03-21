import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  const { title, body } = await req.json();

  const { data: profiles } = await supabase
    .from("profiles")
    .select("fcm_token")
    .not("fcm_token", "is", null)
    .neq("fcm_token", "");

  if (!profiles || profiles.length === 0) {
    return new Response(JSON.stringify({ sent: 0 }), { status: 200 });
  }

  // Appelle send-notification pour chaque token
  let sent = 0;
  for (const profile of profiles) {
    try {
      await supabase.functions.invoke("send-notification", {
        body: { token: profile.fcm_token, title, body },
      });
      sent++;
    } catch (_) {}
  }

  return new Response(JSON.stringify({ sent }), { status: 200 });
});