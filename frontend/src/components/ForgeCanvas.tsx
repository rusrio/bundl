"use client";

import { useEffect, useRef, useCallback } from "react";

interface Token {
  x: number;
  y: number;
  baseX: number;
  baseY: number;
  angle: number;
  orbitRadius: number;
  speed: number;
  size: number;
  color: string;
  label: string;
  opacity: number;
  trail: { x: number; y: number }[];
}

const TOKEN_COLORS = [
  "#f7931a", // BTC orange
  "#627eea", // ETH blue
  "#26a17b", // USDT green
  "#f3ba2f", // BNB yellow
  "#e84142", // AVAX red
  "#8247e5", // MATIC purple
  "#00adef", // LINK blue
  "#ff007a", // UNI pink
];

const TOKEN_LABELS = ["WBTC", "WETH", "LINK", "UNI", "AVAX", "AAVE", "SNX", "CRV"];

export default function ForgeCanvas() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const tokensRef = useRef<Token[]>([]);
  const animFrameRef = useRef<number>(0);
  const scrollProgressRef = useRef(0);
  const mouseRef = useRef({ x: 0, y: 0 });
  const timeRef = useRef(0);

  const initTokens = useCallback((w: number, h: number) => {
    const cx = w / 2;
    const cy = h / 2;
    const tokens: Token[] = [];

    for (let i = 0; i < 8; i++) {
      const angle = (Math.PI * 2 * i) / 8;
      const orbitRadius = Math.min(w, h) * 0.28 + Math.random() * 40;
      tokens.push({
        x: cx + Math.cos(angle) * orbitRadius,
        y: cy + Math.sin(angle) * orbitRadius,
        baseX: cx,
        baseY: cy,
        angle: angle,
        orbitRadius,
        speed: 0.003 + Math.random() * 0.004,
        size: 18 + Math.random() * 12,
        color: TOKEN_COLORS[i],
        label: TOKEN_LABELS[i],
        opacity: 1,
        trail: [],
      });
    }

    tokensRef.current = tokens;
  }, []);

  const draw = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const w = canvas.width;
    const h = canvas.height;
    const cx = w / 2;
    const cy = h / 2;
    const scroll = scrollProgressRef.current;
    const time = timeRef.current;
    timeRef.current += 1;

    // Clear
    ctx.clearRect(0, 0, w, h);

    // Background glow
    const grad = ctx.createRadialGradient(cx, cy, 0, cx, cy, Math.min(w, h) * 0.5);
    grad.addColorStop(0, `rgba(245, 158, 11, ${0.06 + scroll * 0.08})`);
    grad.addColorStop(0.5, `rgba(234, 88, 12, ${0.02 + scroll * 0.04})`);
    grad.addColorStop(1, "transparent");
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, w, h);

    // Connection lines (fade with scroll)
    const lineOpacity = Math.max(0, 1 - scroll * 1.5);
    if (lineOpacity > 0) {
      ctx.strokeStyle = `rgba(245, 158, 11, ${0.06 * lineOpacity})`;
      ctx.lineWidth = 1;
      for (let i = 0; i < tokensRef.current.length; i++) {
        for (let j = i + 1; j < tokensRef.current.length; j++) {
          const a = tokensRef.current[i];
          const b = tokensRef.current[j];
          const dist = Math.hypot(a.x - b.x, a.y - b.y);
          if (dist < 300) {
            ctx.globalAlpha = (1 - dist / 300) * lineOpacity;
            ctx.beginPath();
            ctx.moveTo(a.x, a.y);
            ctx.lineTo(b.x, b.y);
            ctx.stroke();
          }
        }
      }
      ctx.globalAlpha = 1;
    }

    // Update and draw tokens
    tokensRef.current.forEach((token) => {
      // Orbit movement (slows as scroll increases)
      const orbitSpeed = token.speed * (1 - scroll * 0.8);
      token.angle += orbitSpeed;

      // Shrink orbit radius toward center as scroll progresses
      const currentRadius = token.orbitRadius * (1 - scroll * 0.92);
      const targetX = cx + Math.cos(token.angle) * currentRadius;
      const targetY = cy + Math.sin(token.angle) * currentRadius;

      // Mouse repulsion (subtle)
      const mx = mouseRef.current.x;
      const my = mouseRef.current.y;
      const mouseDist = Math.hypot(targetX - mx, targetY - my);
      let repelX = 0;
      let repelY = 0;
      if (mouseDist < 120 && mouseDist > 0) {
        const force = (120 - mouseDist) / 120;
        repelX = ((targetX - mx) / mouseDist) * force * 25;
        repelY = ((targetY - my) / mouseDist) * force * 25;
      }

      // Smooth lerp
      token.x += (targetX + repelX - token.x) * 0.08;
      token.y += (targetY + repelY - token.y) * 0.08;

      // Trail
      token.trail.push({ x: token.x, y: token.y });
      if (token.trail.length > 12) token.trail.shift();

      // Draw trail
      if (token.trail.length > 1) {
        const trailOpacity = Math.max(0, 0.3 * (1 - scroll));
        for (let t = 0; t < token.trail.length - 1; t++) {
          const alpha = (t / token.trail.length) * trailOpacity;
          ctx.strokeStyle = token.color;
          ctx.globalAlpha = alpha;
          ctx.lineWidth = token.size * 0.15 * (t / token.trail.length);
          ctx.beginPath();
          ctx.moveTo(token.trail[t].x, token.trail[t].y);
          ctx.lineTo(token.trail[t + 1].x, token.trail[t + 1].y);
          ctx.stroke();
        }
        ctx.globalAlpha = 1;
      }

      // Token size shrinks when converging
      const drawSize = token.size * (1 - scroll * 0.6);
      const tokenOpacity = Math.max(0.15, 1 - scroll * 0.8);

      // Draw token circle
      ctx.globalAlpha = tokenOpacity;
      ctx.beginPath();
      ctx.arc(token.x, token.y, drawSize, 0, Math.PI * 2);

      // Glow
      const glow = ctx.createRadialGradient(
        token.x, token.y, 0,
        token.x, token.y, drawSize * 2
      );
      glow.addColorStop(0, token.color + "40");
      glow.addColorStop(1, "transparent");
      ctx.fillStyle = glow;
      ctx.fill();

      // Solid circle
      ctx.beginPath();
      ctx.arc(token.x, token.y, drawSize * 0.7, 0, Math.PI * 2);
      ctx.fillStyle = token.color;
      ctx.fill();

      // Label (fade out on scroll)
      if (scroll < 0.6) {
        ctx.globalAlpha = tokenOpacity * (1 - scroll * 1.5);
        ctx.fillStyle = "#fff";
        ctx.font = `${Math.max(9, 11 - scroll * 6)}px Inter, sans-serif`;
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";
        ctx.fillText(token.label, token.x, token.y);
      }

      ctx.globalAlpha = 1;
    });

    // Center Bundl cube (appears as tokens converge)
    const cubeOpacity = Math.max(0, (scroll - 0.3) * 2.5);
    if (cubeOpacity > 0) {
      const cubeSize = 28 + cubeOpacity * 20;
      const pulse = Math.sin(time * 0.03) * 4;

      // Glow ring
      ctx.globalAlpha = cubeOpacity * 0.4;
      ctx.beginPath();
      ctx.arc(cx, cy, cubeSize + 20 + pulse, 0, Math.PI * 2);
      ctx.strokeStyle = "#f59e0b";
      ctx.lineWidth = 2;
      ctx.stroke();

      // Outer glow
      const outerGlow = ctx.createRadialGradient(cx, cy, cubeSize, cx, cy, cubeSize + 50 + pulse);
      outerGlow.addColorStop(0, `rgba(245, 158, 11, ${0.15 * cubeOpacity})`);
      outerGlow.addColorStop(1, "transparent");
      ctx.fillStyle = outerGlow;
      ctx.beginPath();
      ctx.arc(cx, cy, cubeSize + 50 + pulse, 0, Math.PI * 2);
      ctx.fill();

      // Core
      ctx.globalAlpha = cubeOpacity;
      const coreGrad = ctx.createRadialGradient(cx, cy, 0, cx, cy, cubeSize);
      coreGrad.addColorStop(0, "#fbbf24");
      coreGrad.addColorStop(0.6, "#f59e0b");
      coreGrad.addColorStop(1, "#ea580c");
      ctx.fillStyle = coreGrad;
      ctx.beginPath();
      ctx.arc(cx, cy, cubeSize, 0, Math.PI * 2);
      ctx.fill();

      // Inner icon (simplified cube)
      ctx.fillStyle = `rgba(34, 27, 16, ${cubeOpacity * 0.8})`;
      const s = cubeSize * 0.4;
      ctx.fillRect(cx - s, cy - s, s * 0.85, s * 0.85);
      ctx.fillRect(cx + s * 0.15, cy - s, s * 0.85, s * 0.85);
      ctx.fillRect(cx - s, cy + s * 0.15, s * 0.85, s * 0.85);
      ctx.globalAlpha = cubeOpacity * 0.7;
      ctx.fillRect(cx + s * 0.15, cy + s * 0.15, s * 0.85, s * 0.85);

      ctx.globalAlpha = 1;
    }

    // Floating particles (ambient)
    for (let i = 0; i < 30; i++) {
      const px = ((Math.sin(time * 0.005 + i * 2.1) + 1) / 2) * w;
      const py = ((Math.cos(time * 0.004 + i * 1.7) + 1) / 2) * h;
      const ps = 1 + Math.sin(time * 0.02 + i) * 0.5;
      ctx.globalAlpha = 0.15 + Math.sin(time * 0.01 + i) * 0.1;
      ctx.fillStyle = "#f59e0b";
      ctx.beginPath();
      ctx.arc(px, py, ps, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;

    animFrameRef.current = requestAnimationFrame(draw);
  }, []);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const resize = () => {
      const dpr = window.devicePixelRatio || 1;
      canvas.width = window.innerWidth * dpr;
      canvas.height = window.innerHeight * dpr;
      canvas.style.width = `${window.innerWidth}px`;
      canvas.style.height = `${window.innerHeight}px`;
      const ctx = canvas.getContext("2d");
      if (ctx) ctx.scale(dpr, dpr);
      initTokens(window.innerWidth, window.innerHeight);
    };

    const onScroll = () => {
      const maxScroll = document.documentElement.scrollHeight - window.innerHeight;
      // Use only the first viewport height for the animation
      const progress = Math.min(1, window.scrollY / (window.innerHeight * 1.2));
      scrollProgressRef.current = progress;
    };

    const onMouse = (e: MouseEvent) => {
      mouseRef.current = { x: e.clientX, y: e.clientY };
    };

    resize();
    window.addEventListener("resize", resize);
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("mousemove", onMouse, { passive: true });

    animFrameRef.current = requestAnimationFrame(draw);

    return () => {
      cancelAnimationFrame(animFrameRef.current);
      window.removeEventListener("resize", resize);
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("mousemove", onMouse);
    };
  }, [initTokens, draw]);

  return (
    <canvas
      ref={canvasRef}
      style={{
        position: "fixed",
        top: 0,
        left: 0,
        width: "100%",
        height: "100%",
        pointerEvents: "none",
        zIndex: 0,
      }}
    />
  );
}
