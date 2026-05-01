import { createClient } from "@supabase/supabase-js";

const supabaseUrl = import.meta.env.PUBLIC_SUPABASE_URL;
const supabaseKey = import.meta.env.PUBLIC_SUPABASE_KEY;

// Falla ruidoso si las vars no llegan al bundle al hacer build. Astro inlinea
// PUBLIC_* en BUILD TIME — si Railway no las expone durante `npm run build`,
// el cliente queda con placeholder y los signups silenciosamente fallan,
// dejando que el form haga submit nativo (refresh).
if (!supabaseUrl || !supabaseKey) {
  const msg =
    "Supabase credentials missing at build time. Set PUBLIC_SUPABASE_URL and PUBLIC_SUPABASE_KEY as BUILD variables in Railway and redeploy.";
  console.error(msg);
  if (typeof window !== "undefined") {
    window.alert(msg);
  }
  throw new Error(msg);
}

export const supabase = createClient(supabaseUrl, supabaseKey);
