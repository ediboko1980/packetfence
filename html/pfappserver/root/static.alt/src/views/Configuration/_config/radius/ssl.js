import i18n from '@/utils/locale'
import pfFormChosen from '@/components/pfFormChosen'
import pfFormInput from '@/components/pfFormInput'
import pfFormTextarea from '@/components/pfFormTextarea'
import pfFormUpload from '@/components/pfFormUpload'
import { pfSearchConditionType as conditionType } from '@/globals/pfSearch'
import {
  attributesFromMeta,
  validatorsFromMeta
} from '../'
import {
  and,
  not,
  conditional,
  hasRadiusSsls,
  radiusSslExists
} from '@/globals/pfValidators'
import {
  required
} from 'vuelidate/lib/validators'

export const columns = [
  {
    key: 'id',
    label: 'Identifier', // i18n defer
    sortable: true,
    visible: true
  },
  {
    key: 'type',
    label: 'Type', // i18n defer
    sortable: true,
    visible: true
  },
  {
    key: 'buttons',
    label: '',
    locked: true
  }
]

export const fields = [
  {
    value: 'id',
    text: i18n.t('Identifier'),
    types: [conditionType.SUBSTRING]
  }
]

export const config = () => {
  return {
    columns,
    fields,
    rowClickRoute (item) {
      return { name: 'radiusSsl', params: { id: item.id } }
    },
    searchPlaceholder: i18n.t('Search by identifier'),
    searchableOptions: {
      searchApiEndpoint: 'config/ssl_certificates',
      defaultSortKeys: ['id'],
      defaultSearchCondition: {
        op: 'and',
        values: [{
          op: 'or',
          values: [
            { field: 'id', op: 'contains', value: null }
          ]
        }]
      },
      defaultRoute: { name: 'radiusSsls' }
    },
    searchableQuickCondition: (quickCondition) => {
      return {
        op: 'and',
        values: [
          {
            op: 'or',
            values: [
              { field: 'id', op: 'contains', value: quickCondition }
            ]
          }
        ]
      }
    }
  }
}

export const view = (form = {}, meta = {}) => {
  return [
    {
      tab: null,
      rows: [
        {
          label: i18n.t('Identifier'),
          cols: [
            {
              namespace: 'id',
              component: pfFormInput,
              attrs: attributesFromMeta(meta, 'id')
            }
          ]
        },
        {
          label: i18n.t('Type'),
          cols: [
            {
              namespace: 'type',
              component: pfFormChosen,
              attrs: attributesFromMeta(meta, 'type')
            }
          ]
        },
        {
          label: i18n.t('Certificate'),
          cols: [
            {
              namespace: 'cert',
              component: pfFormTextarea,
              attrs: {
                ...attributesFromMeta(meta, 'cert'),
                rows: 6,
                maxRows: 6
              }
            }
          ]
        },
        {
          label: null,
          cols: [
            {
              component: pfFormUpload,
              html: i18n.t('Choose Certificate'),
              attrs: {
                class: 'btn btn-sm btn-outline-secondary mb-3',
                multiple: false,
                accept: 'text/*',
                readAsText: true
              },
              listeners: {
                files: (event) => {
                  const { 0: { percent, result } = {} } = event
                  if (percent === 100 && !!result) {
                    form.cert = result
                  }
                }
              }
            }
          ]
        },
        {
          label: i18n.t('Certificate Authority'),
          cols: [
            {
              namespace: 'ca',
              component: pfFormTextarea,
              attrs: {
                ...attributesFromMeta(meta, 'ca'),
                rows: 6,
                maxRows: 6
              }
            }
          ]
        },
        {
          label: null,
          cols: [
            {
              component: pfFormUpload,
              html: i18n.t('Choose Certificate Authority'),
              attrs: {
                class: 'btn btn-sm btn-outline-secondary mb-3',
                multiple: false,
                accept: 'text/*',
                readAsText: true
              },
              listeners: {
                files: (event) => {
                  const { 0: { percent, result } = {} } = event
                  if (percent === 100 && !!result) {
                    form.ca = result
                  }
                }
              }
            }
          ]
        },
        {
          label: i18n.t('Private Key'),
          cols: [
            {
              namespace: 'key',
              component: pfFormTextarea,
              attrs: {
                ...attributesFromMeta(meta, 'key'),
                rows: 6,
                maxRows: 6
              }
            }
          ]
        },
        {
          label: null,
          cols: [
            {
              component: pfFormUpload,
              html: i18n.t('Choose Private Key'),
              attrs: {
                class: 'btn btn-sm btn-outline-secondary mb-3',
                multiple: false,
                accept: 'text/*',
                readAsText: true
              },
              listeners: {
                files: (event) => {
                  const { 0: { percent, result } = {} } = event
                  if (percent === 100 && !!result) {
                    form.key = result
                  }
                }
              }
            }
          ]
        },
        {
          label: i18n.t('Intermediate CA certificate(s)'),
          cols: [
            {
              namespace: 'intermediate',
              component: pfFormTextarea,
              attrs: {
                ...attributesFromMeta(meta, 'intermediate'),
                rows: 6,
                maxRows: 6
              }
            }
          ]
        },
        {
          label: null,
          cols: [
            {
              component: pfFormUpload,
              html: i18n.t('Choose Intermediate CA Certificate(s)'),
              attrs: {
                class: 'btn btn-sm btn-outline-secondary mb-3',
                multiple: false,
                accept: 'text/*',
                readAsText: true
              },
              listeners: {
                files: (event) => {
                  const { 0: { percent, result } = {} } = event
                  if (percent === 100 && !!result) {
                    form.intermediate = result
                  }
                }
              }
            }
          ]
        }
      ]
    }
  ]
}

export const validators = (form = {}, meta = {}) => {
  const {
    isNew = false,
    isClone = false
  } = meta
  return {
    id: {
      ...validatorsFromMeta(meta, 'id', i18n.t('Identifier')),
      ...{
        [i18n.t('SSL certificate exists.')]: not(and(required, conditional(isNew || isClone), hasRadiusSsls, radiusSslExists))
      }
    }
  }
}