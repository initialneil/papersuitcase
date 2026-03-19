import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const MINIMAX_API_KEY = Deno.env.get("MINIMAX_API_KEY")!;
const MINIMAX_API_URL = "https://api.minimax.chat/v1/text/chatcompletion_v2";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const TIER_LIMITS: Record<string, number> = {
  free: 30,
  pro: 300,
};

const MAX_HISTORY_TURNS = 10;

Deno.serve(async (req) => {
  // CORS
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "authorization, content-type, apikey",
      },
    });
  }

  try {
    // Verify auth
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Get profile for rate limiting
    const { data: profile } = await supabase
      .from("profiles")
      .select("tier, llm_calls_this_month")
      .eq("id", user.id)
      .single();

    if (!profile) {
      return new Response(JSON.stringify({ error: "Profile not found" }), {
        status: 404,
        headers: { "Content-Type": "application/json" },
      });
    }

    const limit = TIER_LIMITS[profile.tier] || 30;
    if (profile.llm_calls_this_month >= limit) {
      return new Response(
        JSON.stringify({
          error: "Rate limit exceeded",
          limit,
          used: profile.llm_calls_this_month,
          tier: profile.tier,
        }),
        {
          status: 429,
          headers: { "Content-Type": "application/json" },
        }
      );
    }

    // Pessimistic counting: increment BEFORE calling MiniMax
    await supabase
      .from("profiles")
      .update({ llm_calls_this_month: profile.llm_calls_this_month + 1 })
      .eq("id", user.id);

    // Parse request
    const {
      paper_title,
      authors,
      abstract: paperAbstract,
      bibtex,
      user_question,
      conversation_history,
    } = await req.json();

    // Build messages
    const systemPrompt = `You are a research assistant helping understand academic papers. Be concise and precise. Here is the paper context:

Title: ${paper_title || "Unknown"}
${authors ? `Authors: ${authors}` : ""}
${paperAbstract ? `Abstract: ${paperAbstract}` : ""}
${bibtex ? `BibTeX: ${bibtex}` : ""}

Answer questions about this paper based on the context provided. If you don't have enough information to answer, say so clearly.`;

    const messages: Array<{ role: string; content: string }> = [
      { role: "system", content: systemPrompt },
    ];

    // Add conversation history (limited to MAX_HISTORY_TURNS)
    if (conversation_history && Array.isArray(conversation_history)) {
      const truncated = conversation_history.slice(-MAX_HISTORY_TURNS);
      for (const msg of truncated) {
        messages.push({ role: msg.role, content: msg.content });
      }
    }

    // Add current question
    messages.push({ role: "user", content: user_question });

    // Call MiniMax API with streaming
    const minimaxResponse = await fetch(MINIMAX_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${MINIMAX_API_KEY}`,
      },
      body: JSON.stringify({
        model: "MiniMax-Text-01",
        messages,
        stream: true,
        max_tokens: 2048,
        temperature: 0.7,
      }),
    });

    if (!minimaxResponse.ok) {
      const errorText = await minimaxResponse.text();
      console.error("MiniMax API error:", errorText);
      return new Response(JSON.stringify({ error: "LLM service error" }), {
        status: 502,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Stream response back to client
    return new Response(minimaxResponse.body, {
      headers: {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        Connection: "keep-alive",
        "Access-Control-Allow-Origin": "*",
      },
    });
  } catch (error) {
    console.error("Edge function error:", error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
