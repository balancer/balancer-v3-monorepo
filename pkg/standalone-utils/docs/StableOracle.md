# Pricing Stable Pool BPTs

In a stable pool with multiple tokens, each token ideally maintains a roughly fixed value (e.g., $1 for stablecoins) and the prices of all tokens are correlated.
However, sometimes that's not the case. For example, when a token depegs from its dollar value. For these moments, we need an oracle that calculates the pool TVL
that is resistant to price manipulation and can accurately predict the pool value.

The goal of the StableOracle contract is to:

1. Compute the market-consistent value of the pool token, based on external prices (p₁, ..., pₙ) provided by oracles.

2. Use those prices to find a set of token balances 𝑥̃ = (𝑥̃₁, ..., 𝑥̃ₙ) that satisfies the pool’s invariant equation and have spot prices aligned with the oracle prices.

## Pool Invariant Equation

The invariant equation is defined as:

F(x₁, ..., xₙ, D) = a(∑xᵢ)(∏xᵢ) - bD(∏xᵢ) - Dⁿ⁺¹ = 0

Where:

- `xᵢ`: balance of token `i`
- `D`: invariant
- `A`: Amplification Factor
- `n`: number of tokens
- `a`: A * n^(2*n)
- `b`: a - n^n

This function defines the constraint that balances must satisfy after swaps or liquidity actions.

## Pricing the Pool Token

To price the pool token:

1. **Find `𝑥̃` and scalar `𝑘̃` such that:**

∇ₓF(𝑥̃, D̃) = 𝑘̃ · p
F(𝑥̃, D̃) = 0

2. **Compute pool value:**

pool_value = ∑ pᵢ \* 𝑥̃ᵢ

3. **Divide pool value by total supply of pool tokens** to get the price per LP token.

## Matching Prices via Gradients

The gradient `∇ₓF` gives the **internal prices** between tokens. We want:

∇ₓF = 𝑘̃ · p

This ensures that the internal pricing mechanism is aligned with **oracle prices**.

Solving the gradient for each xⱼ, we have:

-(∑xᵢ) + c \* D + (k \* rⱼ - 1) \* xⱼ = 0

Where:

- `rᵢ = pᵢ / a`
- `c = b / a`

## Solving the System

The gradient of the invariant is computed and leads to a **linear system**, which is transformed into:

### Equation A.1:

xⱼ = ((kr₁ - 1) / (krⱼ - 1)) \* x₁

Using this, you can express all `xⱼ` in terms of `x₁` and `k`.

Substitute into the gradient equation for j = 1 equations to solve for `x₁`, giving:

x₁ = [cD / (kr₁ - 1)] · [ (∑ 1 / (krᵢ - 1)) - 1 ]⁻¹

And generalize to all `xⱼ`:

xⱼ = [cD / (krⱼ - 1)] · [ (∑ 1 / (krᵢ - 1)) - 1 ]⁻¹

## Final Root-Finding Equation

Let:

T = ∑(1 / (krᵢ - 1)) - 1
P = ∏ (krᵢ - 1)

Then the core equation becomes:

Tⁿ⁺¹ · P = α

Where `α = a · cⁿ⁺¹`. This is a **nonlinear equation in `k`**.

## Solving for k Using Newton's Method

1. Define:

F(k) = T(k)ⁿ⁺¹ · P(k) - α

2. Compute derivatives:

T'(k) = -∑ rᵢ / (krᵢ - 1)²
P'(k) = P · ∑ rᵢ / (krᵢ - 1)
F'(k) = Tⁿ · P · [ (n+1)T' + T ∑ rᵢ / (krᵢ - 1) ]

3. Use Newton’s method:

kₙ₊₁ = kₙ - F(kₙ) / F'(kₙ)

## Root Selection and Initialization

- For even `n`, there's one root.
- For odd `n`, there are two roots. The **smaller one is correct**.
- Safe starting point for Newton's method:

k₀ = min{ 1 + 1/(1+b), 2 - c } / min{rᵢ}

This ensures convergence to the correct solution.
