import pandas as pd

file_path = "data/raw/StormEvents_details-ftp_v1.0_d2022_c20260625.csv"

df = pd.read_csv(file_path)

# Display the first few rows
print("\nFirst 5 Rows:")
print(df.head())

# Number of rows and columns
print("\n(Rows, Columns):")
print(df.shape)

# Column names
print("\nColumns:")
print(df.columns.tolist())

# Data types
print("\nData Types:")
print(df.dtypes)

# Missing States
print("\nMissing States:")
print(df["STATE"].isnull().sum())

# Missing Event Types
print("\nMissing Event Types:")
print(df["EVENT_TYPE"].isnull().sum())


# Duplicate Event IDs
print("\nDuplicate Event IDs:")
print(df["EVENT_ID"].duplicated().sum())

# Number of Event Types
print("\nNumber of Event Types:")
print(df["EVENT_TYPE"].nunique())

# Event Types
print("\nEvent Types:")
print(df["EVENT_TYPE"].value_counts())

# Missing Property Damage Values
print("\nMissing Property Damage Values:")
print(df["DAMAGE_PROPERTY"].isnull().sum())

# Property Damage Values
print("\nDamage Values:")
print(df["DAMAGE_PROPERTY"].value_counts().head(20))

# Missing Crop Damage
print("\nMissing Crop Damage:")
print(df["DAMAGE_CROPS"].isnull().sum())

# Crop Damage
print("\nCrop Damage Values:")
print(df["DAMAGE_CROPS"].value_counts().head(20))

# Begin Date Time Format
dates = pd.to_datetime(
    df["BEGIN_DATE_TIME"],
    format="%d-%b-%y %H:%M:%S",
    errors="coerce"
)

# Begin Date Range
print("\nBegin Date Range:")
print(dates.min())
print(dates.max())

# Invalid Begin Dates
print("\nInvalid Begin Dates:")
print(dates.isnull().sum())

# Year Counts
print("\nYear Counts:")
print(df["YEAR"].value_counts().sort_index())
# Month Counts
print("\nMonth Counts:")
print(df["MONTH_NAME"].value_counts())