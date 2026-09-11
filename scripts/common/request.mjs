const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export async function request(
  apiUrl,
  path,
  options = {},
  {
    maxAttempts = 3,
    retryDelayMs = 10_000,
    retryableStatuses = [502, 503, 504],
  } = {}
) {
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const response = await fetch(`${apiUrl}${path}`, {
        ...options,
        headers: {
          "content-type": "application/json",
          ...(options.headers || {}),
        },
      });

      const text = await response.text();

      let body;
      try {
        body = JSON.parse(text);
      } catch {
        body = text;
      }

      if (response.ok) {
        return body;
      }

      if (
        retryableStatuses.includes(response.status) &&
        attempt < maxAttempts
      ) {
        console.log(
          `${options.method || "GET"} ${path} -> ${response.status}. ` +
          `Retrying in ${retryDelayMs / 1000}s ` +
          `(attempt ${attempt + 1}/${maxAttempts})...`
        );

        await sleep(retryDelayMs);
        continue;
      }

      throw new Error(
        `${options.method || "GET"} ${path} -> ${response.status}: ${text}`
      );
    } catch (error) {
      const isLastAttempt = attempt === maxAttempts;

      if (error instanceof TypeError && !isLastAttempt) {
        console.log(
          `${options.method || "GET"} ${path} -> network error: ${error.message}. ` +
          `Retrying in ${retryDelayMs / 1000}s ` +
          `(attempt ${attempt + 1}/${maxAttempts})...`
        );

        await sleep(retryDelayMs);
        continue;
      }

      throw error;
    }
  }
}
