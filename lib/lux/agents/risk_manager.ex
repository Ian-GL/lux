defmodule Lux.Agents.RiskManager do
  @moduledoc """
  An agent that evaluates trade proposals for risk and executes approved trades.
  """

  use Lux.Agent

  alias Lux.Beams.Hyperliquid.TradeRiskManagementBeam
  require Logger

  def new(opts \\ %{}) do
    Lux.Agent.new(%{
      name: "Risk Management Agent",
      description: "Evaluates and executes trades based on risk assessment",
      goal: "Ensure trades meet risk management criteria before execution",
      capabilities: [:risk_management, :trade_execution],
      llm_config: %{
        api_key: opts[:api_key] || Lux.Config.openai_api_key(),
        model: opts[:model] || "gpt-4o-mini",
        temperature: 0.3,
        json_response: true,
        json_schema: %{
          name: "risk_evaluation",
          schema: %{
            type: "object",
            properties: %{
              execute_trade: %{
                type: "boolean",
                description: "Whether to proceed with trade execution"
              },
              reasoning: %{
                type: "string",
                description: "Detailed explanation of the decision"
              }
            },
            required: ["execute_trade", "reasoning"],
            additionalProperties: false
          },
          strict: true
        },
        messages: [
          %{
            role: "system",
            content: """
            You are a Risk Management Agent responsible for evaluating trade proposals
            and executing trades that meet risk criteria. You will:

            1. Review trade proposals and their rationale
            2. Use the Risk Management Beam to evaluate trades
            3. Execute approved trades
            4. Provide feedback on rejected trades

            Respond with a structured evaluation including whether to execute the trade
            and your reasoning.
            """
          }
        ]
      }
    })
  end

  def evaluate_trade(agent, %{"coin" => _coin} = trade_proposal) do
    Logger.info("Evaluating trade proposal: #{inspect(trade_proposal)}")

    # First get agent's opinion on the trade
    {:ok, evaluation} =
      send_message(agent, """
      Evaluate this trade proposal:
      #{Jason.encode!(trade_proposal, pretty: true)}

      Consider:
      1. Does the rationale make sense?
      2. Is the position size reasonable?
      3. Is the limit price realistic?
      """)

    Logger.info("LLM evaluation: #{inspect(evaluation)}")

    case Jason.decode!(evaluation) do
      %{"execute_trade" => true} ->
        Logger.info("LLM approved trade, running risk management beam")
        # Run the trade through the risk management beam
        case TradeRiskManagementBeam.run(%{
               address: Lux.Config.hyperliquid_account_address(),
               trade: Map.delete(trade_proposal, "rationale")
             }) do
          {:ok, result, _metadata} ->
            Logger.info("Risk management beam result: #{inspect(result)}")
            {:ok, result}

          {:error, reason, _metadata} ->
            Logger.warning("Risk management beam rejected trade: #{inspect(reason)}")
            {:ok, %{status: "rejected", reason: reason}}
        end

      %{"execute_trade" => false, "reasoning" => reason} ->
        Logger.info("LLM rejected trade: #{inspect(reason)}")
        {:ok, %{status: "rejected", reason: reason}}
    end
  end
end
