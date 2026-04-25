(function () {
  "use strict";

  const config = window.geeLive2DConfig || {};
  const modelURL = config.modelUrl ? new URL(config.modelUrl, window.location.href) : null;
  const stage = document.getElementById("stage");
  const loadingOverlay = document.getElementById("loading-overlay");
  const debugStatus = document.getElementById("debug-status");

  let runtimeController = null;
  let paused = false;
  let statusMessage = "";
  let desiredViewport = { offsetX: 0, offsetY: 0, scale: 1 };
  let desiredPosePath = null;
  let desiredExpressionPath = null;
  const nativeFetch = window.fetch.bind(window);

  function trackedRequestLabel(value) {
    try {
      const url = typeof value === "string"
        ? value
        : value instanceof URL
          ? value.toString()
          : value?.url || "";
      if (!url) return null;
      if (!url.includes("/persona/") && !url.includes("/Framework/")) {
        return null;
      }
      const parts = url.split("/");
      return decodeURIComponent(parts[parts.length - 1] || url);
    } catch {
      return null;
    }
  }

  window.fetch = async function trackedFetch(input, init) {
    const label = config.debug ? trackedRequestLabel(input) : null;
    if (label) {
      setStatus(`Fetching\n${label}`);
    }

    try {
      const response = await nativeFetch(input, init);
      if (label && "ok" in response && !response.ok) {
        setStatus(`Fetch ${response.status}\n${label}`);
      }
      return response;
    } catch (error) {
      if (label) {
        setStatus(`Fetch failed\n${label}`);
      }
      throw error;
    }
  };

  function setStatus(message) {
    statusMessage = message || "";
    if (debugStatus) {
      debugStatus.textContent = statusMessage;
      debugStatus.classList.toggle("visible", Boolean(config.debug && statusMessage));
    }
  }

  function setLoading(isLoading) {
    if (!loadingOverlay) return;
    loadingOverlay.classList.toggle("hidden", !isLoading);
  }

  function applyViewport() {
    if (!stage) return;
    const scale = Math.min(Math.max(Number(desiredViewport.scale) || 1, 0.65), 1.8);
    const offsetX = Number(desiredViewport.offsetX) || 0;
    const offsetY = Number(desiredViewport.offsetY) || 0;
    stage.style.transformOrigin = "50% 58%";
    stage.style.transform = `translate(${offsetX}px, ${offsetY}px) scale(${scale})`;
  }

  async function applyDesiredState() {
    applyViewport();
    if (!runtimeController) return;

    if (typeof runtimeController.setPose === "function") {
      await runtimeController.setPose(desiredPosePath);
    }
    if (typeof runtimeController.setExpression === "function") {
      await runtimeController.setExpression(desiredExpressionPath);
    }
  }

  window.geeLive2D = {
    pause() {
      paused = true;
      runtimeController?.pause?.();
    },
    resume() {
      paused = false;
      runtimeController?.resume?.();
    },
    stop() {
      runtimeController?.stop?.();
      runtimeController = null;
    },
    async playMotion(relativePath, motionName) {
      return await runtimeController?.playMotion?.(relativePath, motionName) ?? false;
    },
    async setPose(relativePath) {
      desiredPosePath = relativePath || null;
      if (!runtimeController?.setPose) return true;
      return await runtimeController.setPose(desiredPosePath);
    },
    async setExpression(relativePath) {
      desiredExpressionPath = relativePath || null;
      if (!runtimeController?.setExpression) return true;
      return await runtimeController.setExpression(desiredExpressionPath);
    },
    async setViewport(viewport) {
      desiredViewport = {
        offsetX: Number(viewport?.offsetX) || 0,
        offsetY: Number(viewport?.offsetY) || 0,
        scale: Number(viewport?.scale) || 1,
      };
      applyViewport();
      return true;
    },
    getStatus() {
      return {
        ready: Boolean(runtimeController),
        message: statusMessage,
        modelUrl: config.modelUrl || "",
      };
    },
  };

  function loadOptionalScript(filename) {
    return new Promise((resolve) => {
      const existing = document.querySelector(`script[data-live2d-file="${filename}"]`);
      if (existing) {
        resolve(true);
        return;
      }

      const script = document.createElement("script");
      script.src = new URL(filename, window.location.href).toString();
      script.async = false;
      script.dataset.live2dFile = filename;
      script.onload = () => resolve(true);
      script.onerror = () => {
        script.remove();
        resolve(false);
      };
      document.head.appendChild(script);
    });
  }

  async function loadVendoredRuntime() {
    const candidates = [
      "cubismcore.min.js",
      "live2dcubismcore.min.js",
      "Framework.js",
      "framework.js",
      "live2d-bootstrap.js",
      "bundle.js",
      "LAppDelegate.js",
      "lappdelegate.js",
    ];

    for (const file of candidates) {
      // eslint-disable-next-line no-await-in-loop
      await loadOptionalScript(file);
    }
  }

  function createRuntimeCanvas() {
    const existing = document.getElementById("live2d-runtime");
    if (existing) return existing;
    const runtimeCanvas = document.createElement("canvas");
    runtimeCanvas.id = "live2d-runtime";
    runtimeCanvas.style.position = "absolute";
    runtimeCanvas.style.inset = "0";
    runtimeCanvas.style.width = "100%";
    runtimeCanvas.style.height = "100%";
    stage.appendChild(runtimeCanvas);
    return runtimeCanvas;
  }

  async function tryStartVendoredRuntime() {
    if (!modelURL) return false;

    await loadVendoredRuntime();

    try {
      if (typeof window.geeLive2DBootstrap === "function") {
        runtimeController = await window.geeLive2DBootstrap(
          {
            modelUrl: modelURL.toString(),
            modelPath: config.modelPath,
            debug: Boolean(config.debug),
          },
          {
            stage,
            createRuntimeCanvas,
            setStatus,
          }
        );
      }

      if (!runtimeController) {
        return false;
      }

      await applyDesiredState();
      if (paused) {
        runtimeController.pause?.();
      }
      if (!config.debug) {
        setStatus("");
      }
      setLoading(false);
      return true;
    } catch (error) {
      console.warn("[geeLive2D] vendored runtime bootstrap failed", error);
      runtimeController = null;
      return false;
    }
  }

  (async function initialize() {
    applyViewport();
    setLoading(true);

    const booted = await tryStartVendoredRuntime();
    if (!booted) {
      setLoading(false);
      setStatus("Live2D load failed");
    }
  })();
})();
