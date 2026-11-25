export const UaePassUserType = {
  SOP1: 'SOP1',
  SOP2: 'SOP2',
  SOP3: 'SOP3',
} as const;

export const UaePassProfileType = {
  CitizenOrResident: '1',
  Visitor: '2',
} as const;

export const UaePassGender = {
  Male: 'Male',
  Female: 'Female',
} as const;

const stringFields = [
  'uuid',
  'sub',
  'userType',
  'profileType',
  'unifiedID',
  'unifiedId',
  'fullnameEN',
  'fullnameAR',
  'firstnameEN',
  'firstnameAR',
  'lastnameEN',
  'lastnameAR',
  'titleEN',
  'titleAR',
  'gender',
  'nationalityEN',
  'nationalityAR',
  'email',
  'mobile',
  'idn',
  'idType',
  'spuuid',
  'acr',
] as const;

export type UaePassUserInfo = Readonly<
  Partial<Record<(typeof stringFields)[number], string>> &
  { amr?: readonly string[] } &
  Record<string, unknown>
>;

export function parseUserInfo(data: Record<string, unknown>): UaePassUserInfo | undefined {
  const profile = { ...data };
  for (const key of stringFields) {
    const value = profile[key];
    const blankIdentifier =
      (key === 'uuid' || key === 'sub') && typeof value === 'string' && value.trim() === '';
    if (value === null || blankIdentifier) {
      delete profile[key];
    } else if (value !== undefined && typeof value !== 'string') {
      return undefined;
    }
  }
  if (profile.uuid === undefined && profile.sub === undefined) return undefined;

  const { amr } = profile;
  if (amr === null) {
    delete profile.amr;
  } else if (
    amr !== undefined &&
    (!Array.isArray(amr) || !amr.every((method) => typeof method === 'string'))
  ) {
    return undefined;
  }
  return profile;
}
