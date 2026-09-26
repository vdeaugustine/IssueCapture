using System.Collections;
using UnityEngine;

namespace VinWare.IssueCapture
{
    internal sealed class CaptureRunner : MonoBehaviour
    {
        private Coroutine pending;
        private float deadline;

        internal void CaptureFrame()
        {
            deadline = Time.realtimeSinceStartup + 5;
            pending = StartCoroutine(CaptureAtEndOfFrame());
        }

        private IEnumerator CaptureAtEndOfFrame()
        {
            yield return new WaitForEndOfFrame();
            Texture2D texture = null;
            byte[] png = null;
            try
            {
                if ((long)Screen.width * Screen.height <= 16000000)
                {
                    texture = ScreenCapture.CaptureScreenshotAsTexture();
                    if (texture != null) png = texture.EncodeToPNG();
                    if (png != null && png.Length > 33554432) png = null;
                }
            }
            finally
            {
                if (texture != null) Destroy(texture);
                NativeTransport.FinishCapture(png);
                pending = null;
            }
        }

        private void Update()
        {
            if (pending == null || Time.realtimeSinceStartup <= deadline) return;
            StopCoroutine(pending);
            pending = null;
            NativeTransport.FinishCapture(null);
        }

        private void OnApplicationPause(bool paused)
        {
            if (!paused || pending == null) return;
            StopCoroutine(pending);
            pending = null;
            IssueCapture.CancelCapture();
        }

        private void OnDestroy() { IssueCapture.RunnerDestroyed(this); }
    }
}
