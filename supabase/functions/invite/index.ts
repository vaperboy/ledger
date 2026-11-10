const CODE = /^[A-Z0-9]{3}-?[A-Z0-9]{4}$/;

Deno.serve((req: Request) => {
  const code = (new URL(req.url).searchParams.get("c") ?? "").toUpperCase();
  if (!CODE.test(code)) return new Response("Invalid invite", { status: 400 });
  const dashed = code.includes("-") ? code : `${code.slice(0, 3)}-${code.slice(3)}`;
  return new Response(null, { status: 302, headers: { Location: `ledger://friend/${dashed}`, "Cache-Control": "no-store" } });
});
