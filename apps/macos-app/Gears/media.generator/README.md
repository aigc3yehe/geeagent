# Media Generator

Native Gee Gear for media generation.

V1 uses Gee's global Xenodia channel for image and video generation. API keys
and provider endpoints are configured at the main app provider/channel layer,
not inside this Gear package.

Current Xenodia image models:

- `nano-banana-pro`: supports `n=1`, `async`, `response_format=url`,
  `aspect_ratio`, `resolution`, `output_format`, and reference images.
- `gpt-image-2`: supports `n=1`, `async`, `response_format=url`,
  `aspect_ratio`, `resolution`, and reference images.

Current Xenodia video models:

- `veo3.1`, `veo3.1_fast`, `veo3.1_lite`: task-only Veo3.1 video
  generation through `/v1/videos/generations`. `REFERENCE_2_VIDEO` requires
  `veo3.1_fast`; `TEXT_2_VIDEO` accepts no `imageUrls`; first/last frame mode
  accepts 1-2 image URLs; reference mode accepts 1-3 image URLs.
- `seedance-2`, `seedance-2-fast`: task-only Seedance 2.0 generation through
  `/v1/videos/generations`. Seedance supports 4-15 second durations,
  `first_frame_url` / `last_frame_url`, and multimodal reference image, video,
  or audio URL arrays. First/last frame mode must not be combined with the
  multimodal reference arrays.

Multi-result generation is Gear-level fan-out, not provider `n>1`. The UI and
agent capability accept `batch_count` from 1 to 4 for image and video tasks;
Gee creates one saved Xenodia task per requested result and presents those
child tasks as one batch row in the native workbench.

Reference inputs are model-specific: Nano Banana Pro accepts up to 8 total
images, GPT Image-2 accepts up to 16 total images, Veo accepts up to 3 image
references, and Seedance accepts up to 9 image references. Local files must be
JPEG, PNG, or WebP and 30MB or smaller. Image tasks send local references
through the global Xenodia image request as multipart `image[]`; video tasks
upload local references through the configured global Xenodia
`storage_upload_url` before passing the returned public URL or `asset://` ID to
the video request.

Image generation is treated as a long-running provider task. Xenodia create,
multipart, and task-status requests use a minimum 30-minute timeout floor. A
timed-out status request keeps the local task `running` so polling can continue
instead of marking the task failed while the provider is still generating.
Video generation uses the same long-running task handling and normalized
Xenodia task retrieval path.

The native workbench keeps reusable quick prompts in
`~/Library/Application Support/GeeAgent/gear-data/media.generator/quick-prompts.json`.
Recent reference images from pasted URLs, clipboard images, and local files are
kept in `image-history.json` and can be reused as references from the History
sheet in both image and video modes.
Generated results stay in task records and output caches instead of being added
to this reference history automatically.
Task Apply restores the prompt, model, supported parameters, and references from
an existing task; reuse-as-reference remains a separate image action.
Displayable reference thumbnails can be clicked to open a fit-to-window preview;
`asset://` references remain non-previewable until they resolve to a displayable
URL.
Video results render with native playback in the task workbench: hovering a
video result starts looping preview with sound muted by default, each video
task exposes a sound toggle, and opening the large preview plays the generated
video in place within the preview window.

Audio remains a Xenodia-channel placeholder so future media models can land
without adding Gear-local provider configuration.
