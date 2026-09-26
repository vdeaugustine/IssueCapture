using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using UnityEngine;

namespace VinWare.IssueCapture
{
    internal static class NativeTransport
    {
#if UNITY_IOS && !UNITY_EDITOR && DEVELOPMENT_BUILD
        [DllImport("__Internal")] private static extern int ICUnityInitialize(byte[] bytes, int length);
        [DllImport("__Internal")] private static extern void ICNativeCommand(byte[] bytes, int length);
        [DllImport("__Internal")] private static extern int ICNativeBeginCapture();
        [DllImport("__Internal")] private static extern void ICNativeFinishCapture(byte[] bytes, int length);
        [DllImport("__Internal")] private static extern int ICNativeIsPresenting();
#endif
        internal static bool Initialize(Command command)
        {
#if UNITY_IOS && !UNITY_EDITOR && DEVELOPMENT_BUILD
            byte[] bytes = Encoding.UTF8.GetBytes(JsonUtility.ToJson(command));
            return ICUnityInitialize(bytes, bytes.Length) == 1;
#else
            return false;
#endif
        }

        internal static void Send(Command command)
        {
#if UNITY_IOS && !UNITY_EDITOR && DEVELOPMENT_BUILD
            byte[] bytes = Encoding.UTF8.GetBytes(JsonUtility.ToJson(command));
            if (bytes.Length <= 65536) ICNativeCommand(bytes, bytes.Length);
#endif
        }

        internal static bool BeginCapture()
        {
#if UNITY_IOS && !UNITY_EDITOR && DEVELOPMENT_BUILD
            return ICNativeBeginCapture() == 1;
#else
            return false;
#endif
        }

        internal static void FinishCapture(byte[] png)
        {
#if UNITY_IOS && !UNITY_EDITOR && DEVELOPMENT_BUILD
            ICNativeFinishCapture(png, png == null ? 0 : png.Length);
#endif
        }

        internal static bool IsPresenting
        {
            get
            {
#if UNITY_IOS && !UNITY_EDITOR && DEVELOPMENT_BUILD
                return ICNativeIsPresenting() == 1;
#else
                return false;
#endif
            }
        }

        internal static string SourceFile(string file)
        {
            string normalized = (file ?? "").Replace('\\', '/');
            int assets = normalized.LastIndexOf("/Assets/", StringComparison.Ordinal);
            return assets >= 0 ? normalized.Substring(assets + 1) : Path.GetFileName(normalized);
        }

        internal static void RequireIdentifier(string value, string parameter)
        {
            if (string.IsNullOrEmpty(value) || value.Length > 200)
                throw new ArgumentException("Use a static semantic identifier of 1–200 characters.", parameter);
        }
    }
}
