import streamlit as st
import pandas as pd
from pathlib import Path
from datetime import date

DATA_FILE = Path("oscp_tracker.csv")

columns = [
    "Date",
    "Platform",
    "Box Name",
    "IP",
    "Difficulty",
    "Status",
    "Initial Access",
    "Privilege Escalation",
    "User Flag",
    "Root Flag",
    "Notes"
]

if not DATA_FILE.exists():
    pd.DataFrame(columns=columns).to_csv(DATA_FILE, index=False)

st.set_page_config(page_title="VibeHack OSCP Tracker", layout="wide")

st.title("VibeHack OSCP Practice Tracker")

df = pd.read_csv(DATA_FILE)

with st.form("add_box"):
    st.subheader("Add / Track Machine")

    col1, col2, col3 = st.columns(3)

    with col1:
        platform = st.selectbox("Platform", ["Hack The Box", "TryHackMe", "Proving Grounds", "VulnHub", "Other"])
        box_name = st.text_input("Box Name")
        ip = st.text_input("Target IP")

    with col2:
        difficulty = st.selectbox("Difficulty", ["Easy", "Medium", "Hard", "Unknown"])
        status = st.selectbox("Status", ["Not Started", "Recon", "Initial Access", "Privilege Escalation", "Completed", "Stuck"])
        today = st.date_input("Date", date.today())

    with col3:
        initial_access = st.checkbox("Initial Access")
        privesc = st.checkbox("Privilege Escalation")
        user_flag = st.checkbox("User Flag")
        root_flag = st.checkbox("Root/Admin Flag")

    notes = st.text_area("Notes / What you learned")

    submitted = st.form_submit_button("Save Machine")

    if submitted:
        new_row = {
            "Date": today,
            "Platform": platform,
            "Box Name": box_name,
            "IP": ip,
            "Difficulty": difficulty,
            "Status": status,
            "Initial Access": initial_access,
            "Privilege Escalation": privesc,
            "User Flag": user_flag,
            "Root Flag": root_flag,
            "Notes": notes
        }

        df = pd.concat([df, pd.DataFrame([new_row])], ignore_index=True)
        df.to_csv(DATA_FILE, index=False)
        st.success("Machine saved!")

st.subheader("Progress Dashboard")

total = len(df)
completed = len(df[df["Status"] == "Completed"])
st.metric("Total Machines", total)
st.metric("Completed", completed)

st.dataframe(df, use_container_width=True)

st.subheader("Export")
st.download_button(
    "Download CSV",
    df.to_csv(index=False),
    "oscp_tracker.csv",
    "text/csv"
)
