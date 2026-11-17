# Spectre 0.4 external invoice approval demo
#
# Run from a Spectre 0.4 checkout:
#   mix run /path/to/spectre_blog/examples/spectre_0_4_external_invoice_approval.exs
#
# This is a transport-independent GAM protocol demo based on the core
# docs/examples/external_approval.exs fixture.
# It does NOT send a real invoice. Its side effect notifies the test process.

defmodule InvoiceApprovalDemo.Transport do
  @behaviour Spectre.Server.GAM.Managed.Approval

  def send_message(message, opts) do
    send(Keyword.fetch!(opts, :receiver), {:wire, message})
    {:ok, :queued}
  end
end

defmodule InvoiceApprovalDemo.Effect do
  @behaviour Spectre.Server.GAM.EffectAdapter

  def execute_effect(:send, args, _) do
    send(Process.whereis(InvoiceApprovalDemo.Consumer), {:invoice_dispatched, args})
    {:ok, %{simulated: true}}
  end
end

defmodule InvoiceApprovalDemo.Package do
  use Spectre.Stack.Installable, id: :invoice_demo, version: "0.1.0"

  def effects(_) do
    %{
      invoice_send: %{
        contract: 1,
        adapter: InvoiceApprovalDemo.Effect,
        operation: :send,
        side_effect: :non_idempotent,
        material: :arguments,
        partition: [],
        schema_hash: nil,
        config: %{}
      }
    }
  end
end

defmodule InvoiceApprovalDemo.AI do
  use Spectre.Stack
  install InvoiceApprovalDemo.Package
end

defmodule InvoiceApprovalDemo.CustomerServer do
  use Spectre.Server

  def handle_flow({:billing, :send}, _input, ctx) do
    propose(
      ctx,
      :invoice_send,
      %{
        "invoice_id" => "INV-104",
        "to" => "billing@example.test",
        "amount_cents" => 125_000,
        "currency" => "EUR"
      },
      on_result: :invoice_result
    )
  end

  def handle_result(:invoice_result, result, ctx) do
    send(Process.whereis(InvoiceApprovalDemo.Consumer), {:invoice_result, result})
    no_response(ctx)
  end

  def handle_result(tag, result, ctx), do: super(tag, result, ctx)
end

defmodule InvoiceApprovalDemo.CustomerAgent do
  use Spectre.Agent,
    stack: InvoiceApprovalDemo.AI,
    server: InvoiceApprovalDemo.CustomerServer

  router strategies: [:regex]

  flow :billing do
    on(:send, regex: ~r/^send invoice INV-104$/i)
  end
end

defmodule InvoiceApprovalDemo.AdminServer do
  use Spectre.Server

  def handle_flow(:unmatched, _input, ctx),
    do: respond(ctx, "Approval requests arrive through the trusted consumer.")
end

defmodule InvoiceApprovalDemo.AdminAgent do
  use Spectre.Agent,
    stack: InvoiceApprovalDemo.AI,
    server: InvoiceApprovalDemo.AdminServer
end

defmodule InvoiceApprovalDemo.Runner do
  alias Spectre.Server

  def run(choice) when choice in [:confirm, :reject] do
    {public, private} = :crypto.generate_key(:eddsa, :ed25519)
    human = %{kind: :human, attributes: %{"subject" => "billing-admin"}}
    authorization = "billing-admin:invoice-consent"
    deadline = System.system_time(:millisecond) + 60_000
    transport = {InvoiceApprovalDemo.Transport, [receiver: self()]}

    {:ok, customer} =
      Server.start_link(
        agent: InvoiceApprovalDemo.CustomerAgent,
        consumer: self(),
        identity: %{subject: "customer-42"},
        gam: [
          operations: %{
            invoice_send: [
              confirm: true,
              message: "Send invoice INV-104 for EUR 1,250 to billing@example.test?",
              approver: {:external, "spectre://admin/billing"}
            ]
          },
          approvals: [
            address: "spectre://customer/billing",
            transport: transport,
            approvers: %{
              "spectre://admin/billing" => [
                principal: human,
                public_key: public,
                mandate_ref: authorization,
                expires_at: deadline
              ]
            }
          ]
        ]
      )

    {:ok, admin} =
      Server.start_link(
        agent: InvoiceApprovalDemo.AdminAgent,
        consumer: self(),
        identity: %{subject: "billing-admin"},
        gam: [
          approvals: [
            address: "spectre://admin/billing",
            transport: transport,
            signer: [
              principal: human,
              private_key: private,
              mandate_ref: authorization,
              expires_at: deadline
            ]
          ]
        ]
      )

    try do
      {:ok, customer_view} = Server.gam_view(customer)
      {:ok, admin_view} = Server.gam_view(admin)
      true = customer_view.opening.domain_ref != admin_view.opening.domain_ref

      {:ok, _interaction} = Server.input(customer, "send invoice INV-104")

      request = wire("approval.request")
      :ok = Server.receive_approval(admin, request)

      receive do
        {Server, ^admin, {:approval_request, ^request}} ->
          # Simulates an authenticated human UI displaying the exact request.
          IO.puts("Administrator sees: " <> request["rendered_payload"])
      after
        5_000 -> raise "Admin did not receive approval request"
      end

      no_invoice!()
      :ok = Server.approval_presented(admin, request["id"])
      :ok = Server.receive_approval(customer, wire("approval.presented"))

      receive do
        {Server, ^customer, {:pending, _, _}} -> :ok
      after
        5_000 -> raise "Customer did not acquire consent wait"
      end

      no_invoice!()
      # In a production app, an independently authenticated human explicitly
      # chooses this value in a UI. A model must never call approval_decide/3.
      :ok = Server.approval_decide(admin, request["id"], choice)
      decision = wire("approval.decision")
      {:ok, _} = Server.receive_approval(customer, decision)

      receive do
        {:invoice_result, {:governed, %{outcome: %{status: :succeeded}}}}
            when choice == :confirm ->
          receive do
            {:invoice_dispatched,
             %{"invoice_id" => "INV-104", "to" => "billing@example.test"}} ->
              :ok
          after
            5_000 -> raise "Confirmed invoice effect did not execute"
          end

        {:invoice_result, {:consent, :rejected}} when choice == :reject ->
          no_invoice!()
      after
        5_000 -> raise "Approval did not produce an invoice result"
      end

      {:error, _} = Server.receive_approval(customer, decision)
      no_invoice!()

      IO.puts("#{choice}: passed; distinct GAM Domains, signed consent, replay refused")
    after
      GenServer.stop(customer)
      GenServer.stop(admin)
    end
  end

  defp wire(type) do
    receive do
      {:wire, %{"type" => ^type} = message} -> message
    after
      5_000 -> raise "Missing approval message: #{type}"
    end
  end

  defp no_invoice! do
    receive do
      {:invoice_dispatched, _} -> raise "Unauthorized or duplicated invoice effect"
    after
      0 -> :ok
    end
  end
end

Process.register(self(), InvoiceApprovalDemo.Consumer)
InvoiceApprovalDemo.Runner.run(:confirm)
InvoiceApprovalDemo.Runner.run(:reject)
