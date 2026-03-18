"use client";

import { useCallback, useEffect, useRef } from "react";

interface OrbitalNode {
  angle: number;
  radius: number;
  speed: number;
  size: number;
  label: string;
  color: string;
  drift: number;
  trail: { x: number; y: number }[];
}

const NODES: Array<Pick<OrbitalNode, "label" | "color">> = [
  { label: "BTC", color: "#f4b44e" },
  { label: "ETH", color: "#9aa7ff" },
  { label: "UNI", color: "#ff7cab" },
  { label: "LINK", color: "#6ec5ff" },
  { label: "AAVE", color: "#87d0b4" },
  { label: "CRV", color: "#ff8e67" },
];

export default function ForgeCanvas() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const frameRef = useRef<number>(0);
  const nodesRef = useRef<OrbitalNode[]>([]);
  const scrollRef = useRef(0);
  const pointerRef = useRef({ x: 0, y: 0, active: false });
  const timeRef = useRef(0);

  const initializeNodes = useCallback((width: number, height: number) => {
    const baseRadius = Math.min(width, height) * 0.22;

    nodesRef.current = NODES.map((node, index) => ({
      angle: (Math.PI * 2 * index) / NODES.length,
      radius: baseRadius + (index % 3) * 34,
      speed: 0.0017 + index * 0.00018,
      size: 10 + (index % 3) * 2,
      label: node.label,
      color: node.color,
      drift: 12 + index * 1.6,
      trail: [],
    }));
  }, []);

  const drawBackground = (
    ctx: CanvasRenderingContext2D,
    width: number,
    height: number,
    cx: number,
    cy: number,
    scroll: number,
  ) => {
    const radial = ctx.createRadialGradient(cx, cy, 0, cx, cy, Math.min(width, height) * 0.7);
    radial.addColorStop(0, `rgba(245, 158, 11, ${0.06 + scroll * 0.05})`);
    radial.addColorStop(0.45, `rgba(99, 76, 38, ${0.12 + scroll * 0.04})`);
    radial.addColorStop(1, "rgba(34, 27, 16, 0)");
    ctx.fillStyle = radial;
    ctx.fillRect(0, 0, width, height);

    ctx.strokeStyle = "rgba(255, 245, 225, 0.035)";
    ctx.lineWidth = 1;

    for (let i = -2; i <= 2; i++) {
      const y = cy + i * height * 0.12;
      ctx.beginPath();
      ctx.moveTo(width * 0.12, y);
      ctx.lineTo(width * 0.88, y);
      ctx.stroke();
    }

    for (let i = -2; i <= 2; i++) {
      const x = cx + i * width * 0.11;
      ctx.beginPath();
      ctx.moveTo(x, height * 0.18);
      ctx.lineTo(x, height * 0.82);
      ctx.stroke();
    }
  };

  const drawRings = (
    ctx: CanvasRenderingContext2D,
    cx: number,
    cy: number,
    width: number,
    height: number,
    scroll: number,
    time: number,
  ) => {
    const ringSet = [0.14, 0.22, 0.31];

    ringSet.forEach((multiplier, index) => {
      const radius = Math.min(width, height) * multiplier * (1 - scroll * 0.14);
      ctx.beginPath();
      ctx.arc(cx, cy, radius, 0, Math.PI * 2);
      ctx.strokeStyle = `rgba(255, 233, 196, ${0.06 - index * 0.012})`;
      ctx.lineWidth = 1;
      ctx.stroke();
    });

    ctx.beginPath();
    ctx.arc(cx, cy, Math.min(width, height) * (0.17 + Math.sin(time * 0.01) * 0.0025), 0, Math.PI * 2);
    ctx.strokeStyle = `rgba(245, 158, 11, ${0.12 + scroll * 0.08})`;
    ctx.lineWidth = 1.2;
    ctx.stroke();
  };

  const drawCore = (
    ctx: CanvasRenderingContext2D,
    cx: number,
    cy: number,
    width: number,
    height: number,
    scroll: number,
    time: number,
  ) => {
    const coreSize = Math.min(width, height) * 0.052 + scroll * 10;
    const pulse = Math.sin(time * 0.018) * 3;

    const outerGlow = ctx.createRadialGradient(cx, cy, coreSize * 0.4, cx, cy, coreSize * 3.4 + pulse);
    outerGlow.addColorStop(0, `rgba(245, 158, 11, ${0.18 + scroll * 0.12})`);
    outerGlow.addColorStop(1, "rgba(245, 158, 11, 0)");
    ctx.fillStyle = outerGlow;
    ctx.beginPath();
    ctx.arc(cx, cy, coreSize * 3.4 + pulse, 0, Math.PI * 2);
    ctx.fill();

    const coreGradient = ctx.createLinearGradient(cx - coreSize, cy - coreSize, cx + coreSize, cy + coreSize);
    coreGradient.addColorStop(0, "#ffd68d");
    coreGradient.addColorStop(0.55, "#f59e0b");
    coreGradient.addColorStop(1, "#9a4d12");

    ctx.save();
    ctx.translate(cx, cy);
    ctx.rotate(Math.PI / 4 + time * 0.0008);
    ctx.fillStyle = coreGradient;
    ctx.fillRect(-coreSize, -coreSize, coreSize * 2, coreSize * 2);

    ctx.fillStyle = "rgba(34, 27, 16, 0.82)";
    const inner = coreSize * 0.42;
    ctx.fillRect(-inner, -inner, inner * 0.82, inner * 0.82);
    ctx.fillRect(inner * 0.18, -inner, inner * 0.82, inner * 0.82);
    ctx.fillRect(-inner, inner * 0.18, inner * 0.82, inner * 0.82);
    ctx.globalAlpha = 0.76;
    ctx.fillRect(inner * 0.18, inner * 0.18, inner * 0.82, inner * 0.82);
    ctx.restore();
    ctx.globalAlpha = 1;
  };

  const drawNodes = (
    ctx: CanvasRenderingContext2D,
    cx: number,
    cy: number,
    width: number,
    height: number,
    scroll: number,
    time: number,
  ) => {
    const pointer = pointerRef.current;
    const labelAlpha = Math.max(0, 0.55 - scroll * 0.7);

    nodesRef.current.forEach((node, index) => {
      node.angle += node.speed * (1 - scroll * 0.35);

      const breathing = Math.sin(time * 0.012 + index) * node.drift;
      const currentRadius = Math.max(42, node.radius * (1 - scroll * 0.52) + breathing);
      let x = cx + Math.cos(node.angle) * currentRadius;
      let y = cy + Math.sin(node.angle) * currentRadius * 0.82;

      if (pointer.active) {
        const distance = Math.hypot(pointer.x - x, pointer.y - y);
        if (distance < 180 && distance > 0) {
          const force = (180 - distance) / 180;
          x -= ((pointer.x - x) / distance) * force * 10;
          y -= ((pointer.y - y) / distance) * force * 10;
        }
      }

      node.trail.push({ x, y });
      if (node.trail.length > 14) node.trail.shift();

      if (node.trail.length > 1) {
        for (let i = 0; i < node.trail.length - 1; i++) {
          const alpha = (i / node.trail.length) * 0.18 * (1 - scroll * 0.4);
          ctx.strokeStyle = node.color;
          ctx.globalAlpha = alpha;
          ctx.lineWidth = 1.2;
          ctx.beginPath();
          ctx.moveTo(node.trail[i].x, node.trail[i].y);
          ctx.lineTo(node.trail[i + 1].x, node.trail[i + 1].y);
          ctx.stroke();
        }
        ctx.globalAlpha = 1;
      }

      ctx.beginPath();
      ctx.moveTo(cx, cy);
      ctx.lineTo(x, y);
      ctx.strokeStyle = `rgba(255, 224, 166, ${0.05 - scroll * 0.015})`;
      ctx.lineWidth = 1;
      ctx.stroke();

      const glow = ctx.createRadialGradient(x, y, 0, x, y, node.size * 2.6);
      glow.addColorStop(0, `${node.color}44`);
      glow.addColorStop(1, `${node.color}00`);
      ctx.fillStyle = glow;
      ctx.beginPath();
      ctx.arc(x, y, node.size * 2.6, 0, Math.PI * 2);
      ctx.fill();

      ctx.fillStyle = node.color;
      ctx.beginPath();
      ctx.arc(x, y, node.size * (0.62 - scroll * 0.1), 0, Math.PI * 2);
      ctx.fill();

      if (labelAlpha > 0) {
        ctx.globalAlpha = labelAlpha;
        ctx.fillStyle = "rgba(248, 239, 223, 0.82)";
        ctx.font = "500 10px Inter, sans-serif";
        ctx.textAlign = "center";
        ctx.fillText(node.label, x, y - 18);
        ctx.globalAlpha = 1;
      }
    });
  };

  const drawDust = (
    ctx: CanvasRenderingContext2D,
    width: number,
    height: number,
    time: number,
  ) => {
    for (let i = 0; i < 18; i++) {
      const x = ((Math.sin(time * 0.0028 + i * 1.7) + 1) / 2) * width;
      const y = ((Math.cos(time * 0.0032 + i * 2.2) + 1) / 2) * height;
      const size = 0.8 + ((Math.sin(time * 0.015 + i) + 1) / 2) * 1.4;
      ctx.globalAlpha = 0.08 + ((Math.sin(time * 0.01 + i) + 1) / 2) * 0.08;
      ctx.fillStyle = "#f6d08a";
      ctx.beginPath();
      ctx.arc(x, y, size, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  };

  const draw = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const width = canvas.width;
    const height = canvas.height;
    const cx = width / 2;
    const cy = height / 2;
    const scroll = scrollRef.current;
    const time = timeRef.current;
    timeRef.current += 1;

    ctx.clearRect(0, 0, width, height);

    drawBackground(ctx, width, height, cx, cy, scroll);
    drawRings(ctx, cx, cy, width, height, scroll, time);
    drawNodes(ctx, cx, cy, width, height, scroll, time);
    drawCore(ctx, cx, cy, width, height, scroll, time);
    drawDust(ctx, width, height, time);

    frameRef.current = window.requestAnimationFrame(draw);
  }, [drawBackground, drawCore, drawDust, drawNodes, drawRings]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const resize = () => {
      const width = window.innerWidth;
      const height = window.innerHeight;
      const dpr = Math.min(window.devicePixelRatio || 1, 2);

      canvas.width = Math.floor(width * dpr);
      canvas.height = Math.floor(height * dpr);
      canvas.style.width = `${width}px`;
      canvas.style.height = `${height}px`;

      const ctx = canvas.getContext("2d");
      if (!ctx) return;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

      initializeNodes(width, height);
    };

    const onScroll = () => {
      scrollRef.current = Math.min(1, window.scrollY / (window.innerHeight * 1.4));
    };

    const onPointerMove = (event: MouseEvent) => {
      pointerRef.current = {
        x: event.clientX,
        y: event.clientY,
        active: true,
      };
    };

    const onPointerLeave = () => {
      pointerRef.current.active = false;
    };

    resize();
    onScroll();

    window.addEventListener("resize", resize);
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("mousemove", onPointerMove, { passive: true });
    window.addEventListener("mouseout", onPointerLeave);

    frameRef.current = window.requestAnimationFrame(draw);

    return () => {
      window.cancelAnimationFrame(frameRef.current);
      window.removeEventListener("resize", resize);
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("mousemove", onPointerMove);
      window.removeEventListener("mouseout", onPointerLeave);
    };
  }, [draw, initializeNodes]);

  return (
    <canvas
      ref={canvasRef}
      aria-hidden="true"
      style={{
        position: "fixed",
        inset: 0,
        width: "100%",
        height: "100%",
        pointerEvents: "none",
        zIndex: 0,
        opacity: 0.96,
      }}
    />
  );
}
