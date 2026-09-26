using System;

namespace VinWare.IssueCapture
{
    [Serializable]
    internal sealed class ScreenContext
    {
        public string id, parentID, stableID, name, typeName, file;
        public int line;
    }

    [Serializable]
    internal sealed class Command
    {
        public string operation, session, category, name, result, file;
        public string projectID = null, sourceRevision = null;
        public int eventLimit = 50, eventByteLimit = 262144, line;
        public bool active;
        public ScreenContext screen;
    }
}
