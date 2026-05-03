# Media Generator

Native Gee Gear for media generation.

V1 uses Gee's global Xenodia channel for image generation. API keys and provider
endpoints are configured at the main app provider/channel layer, not inside this
Gear package.

Current Xenodia image models:

- `nano-banana-pro`: supports `n=1`, `async`, `response_format=url`,
  `aspect_ratio`, `resolution`, `output_format`, and reference images.
- `gpt-image-2`: supports `n=1`, `async`, `response_format=url`,
  `aspect_ratio`, `resolution`, and reference images.

Multi-image generation is Gear-level fan-out, not provider `n>1`. The UI and
agent capability accept `batch_count` from 1 to 4; Gee creates one saved
Xenodia `n=1` task per requested image and presents those child tasks as one
batch row in the native workbench.

Reference inputs are model-specific: Nano Banana Pro accepts up to 8 total
images, and GPT Image-2 accepts up to 16 total images. Local files must be JPEG,
PNG, or WebP and 30MB or smaller. Local references are sent through the global
Xenodia image request as multipart `image[]`; remote reference URLs are sent as
`image_input`.

Image generation is treated as a long-running provider task. Xenodia create,
multipart, and task-status requests use a minimum 30-minute timeout floor. A
timed-out status request keeps the local task `running` so polling can continue
instead of marking the task failed while the provider is still generating.

The native workbench keeps reusable quick prompts in
`~/Library/Application Support/GeeAgent/gear-data/media.generator/quick-prompts.json`.
Recent reference images from pasted URLs and local files are kept in
`image-history.json` and can be reused as references from the History sheet.
Generated results stay in task records and output caches instead of being added
to this reference history automatically.
Task Apply restores the prompt, model, supported parameters, and references from
an existing task; reuse-as-reference remains a separate image action.

Video and audio tabs are present as Xenodia-channel placeholders so future media
models can land without adding Gear-local provider configuration.
