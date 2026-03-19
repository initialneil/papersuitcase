import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (_req) => {
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    // Clear old trending scores
    await supabase.from("trending_scores").delete().neq("id", 0);

    // Get papers with recent activity and multiple readers
    const thirtyDaysAgo = new Date(
      Date.now() - 30 * 24 * 60 * 60 * 1000
    ).toISOString();

    const { data: candidates } = await supabase
      .from("shared_catalog")
      .select("id, reader_count, last_seen_at")
      .gte("last_seen_at", thirtyDaysAgo)
      .gt("reader_count", 1)
      .order("reader_count", { ascending: false })
      .limit(100);

    if (candidates && candidates.length > 0) {
      const maxReaderCount = candidates[0].reader_count;

      const scores = candidates.map((c: Record<string, unknown>) => {
        const recencyDays =
          (Date.now() - new Date(c.last_seen_at as string).getTime()) /
          (1000 * 60 * 60 * 24);
        const recencyWeight = Math.max(0.1, 1 - recencyDays / 30);
        const normalizedReaders =
          (c.reader_count as number) / maxReaderCount;
        return {
          catalog_id: c.id,
          score: normalizedReaders * recencyWeight,
        };
      });

      await supabase.from("trending_scores").insert(scores);
    }

    return new Response(
      JSON.stringify({
        success: true,
        computed: candidates?.length ?? 0,
      }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Trending computation error:", error);
    return new Response(
      JSON.stringify({ error: "Computation failed" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
